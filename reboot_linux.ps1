param(
    [string]$SerialFragment = "0000_0000_0000_0001",
    [char]  $PreferredLetter = 'R',
    [switch]$OpenRefind
)

# Find exactly one disk by serial fragment
$rx = [regex]::Escape($SerialFragment)
$disks = Get-Disk | Where-Object { $_.SerialNumber -and $_.SerialNumber -match $rx }

if (-not $disks) {
    Write-Host "No disk found with serial fragment: $SerialFragment"
    return
}
if ($disks.Count -gt 1) {
    Write-Host "More than one disk matches '$SerialFragment'. Be more specific. Matching disks:"
    $disks | Select-Object Number, FriendlyName, SerialNumber, Size | Format-Table -AutoSize
    return
}

$disk = $disks | Select-Object -First 1

# EFI System Partition (ESP) GPT type GUID
$espGuid = "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}"

# Locate EFI-like partition on the matched disk
$partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction Stop

$esp = $partitions | Where-Object {
    ($_.GptType -eq $espGuid) -or ($_.IsSystem -eq $true) -or ($_.Type -match 'System')
} | Select-Object -First 1

# Fallback detection: small FAT partition (<2GB)
if (-not $esp) {
    $esp = $partitions | Where-Object {
        $_.Size -lt 2GB -and
        ((Get-Volume -Partition $_ -ErrorAction SilentlyContinue).FileSystem -match '^FAT')
    } | Select-Object -First 1
}

if (-not $esp) {
    Write-Host "No EFI-like partition found on disk $($disk.Number)."
    return
}

Write-Host "Found EFI partition number: $($esp.PartitionNumber) on disk number: $($disk.Number)"

$letter = $PreferredLetter

# If PreferredLetter is already in use, ask user what to do (unmount & continue, or cancel)
$existingPartition = Get-Partition -DriveLetter $letter -ErrorAction SilentlyContinue
$existingVolume    = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue

if ($existingPartition -or $existingVolume) {

    Write-Host ""
    Write-Host "Drive letter ${letter}: is already in use." -ForegroundColor Yellow

    if ($existingPartition) {
        Write-Host ("Current mapping: Disk={0}, Partition={1}" -f $existingPartition.DiskNumber, $existingPartition.PartitionNumber)
    } elseif ($existingVolume) {
        Write-Host ("Current mapping: Volume={0}, FileSystem={1}, Label={2}" -f $existingVolume.UniqueId, $existingVolume.FileSystem, $existingVolume.FileSystemLabel)
    }

    do {
        Write-Host ""
        Write-Host "Choose an option:"
        Write-Host "1 - Unmount ${letter}: and continue"
        Write-Host "2 - Cancel the whole script"
        $choice = (Read-Host "Your choice [1/2]").Trim()
    } until ($choice -in @('1','2'))

    if ($choice -eq '2') {
        Write-Host "Cancelled by user." -ForegroundColor Cyan
        return
    }

    # Option 1: remove existing access path and continue
    try {
        if ($existingPartition) {
            Remove-PartitionAccessPath -DiskNumber $existingPartition.DiskNumber `
                                      -PartitionNumber $existingPartition.PartitionNumber `
                                      -AccessPath "${letter}:" -ErrorAction Stop
        } else {
            # Fallback attempt when only volume was resolvable
            Remove-PartitionAccessPath -DriveLetter $letter -AccessPath "${letter}:" -ErrorAction Stop
        }

        Write-Host "Unmounted ${letter}:, continuing..." -ForegroundColor Green
    } catch {
        Write-Host "Unmount error on ${letter}: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
}

# Mount the ESP to PreferredLetter
try {
    Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $esp.PartitionNumber -AccessPath "${letter}:" -ErrorAction Stop
    Write-Host "Partition mounted to ${letter}:"
} catch {
    Write-Host "Mount error: $($_.Exception.Message)"
    return
}

# Locate refind.conf in common paths
$refind1 = "${letter}:\EFI\refind\refind.conf"
$refind2 = "${letter}:\EFI\BOOT\refind.conf"

$refind = if (Test-Path $refind1) { $refind1 } elseif (Test-Path $refind2) { $refind2 } else { $null }

if ($refind) {
    Write-Host "Found: $refind"
    if ($OpenRefind) { notepad $refind }
} else {
    Write-Host "refind.conf not found under EFI\. Searching..."
    Get-ChildItem "${letter}:\EFI" -Recurse -Filter "refind.conf" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
}

Write-Host "To unmount: Remove-PartitionAccessPath -DiskNumber $($disk.Number) -PartitionNumber $($esp.PartitionNumber) -AccessPath ${letter}:"

# --- Set default_selection to vmlinuz in refind.conf ---

if (-not $refind) {
    Write-Host "Cannot edit refind.conf because it was not found."
    return
}

$targetValue = 'default_selection "vmlinuz"'

try {
    $content = Get-Content -LiteralPath $refind -ErrorAction Stop
} catch {
    Write-Host "Read error: $($_.Exception.Message)"
    return
}

# Find active (uncommented) default_selection line
$activeLineIndex = -1
for ($i = 0; $i -lt $content.Count; $i++) {
    if ($content[$i] -match '^\s*default_selection\s+') {
        $activeLineIndex = $i
        break
    }
}

if ($activeLineIndex -ge 0) {
    # Active default_selection exists - replace it
    Write-Host "Found active default_selection at line $($activeLineIndex + 1): $($content[$activeLineIndex])"
    $content[$activeLineIndex] = $targetValue
    Write-Host "Replaced with: $targetValue"
} else {
    # No active default_selection - add it after the first commented one or at the end
    Write-Host "No active default_selection found. Adding new line."
    
    $insertIndex = -1
    for ($i = 0; $i -lt $content.Count; $i++) {
        if ($content[$i] -match '^\s*#\s*default_selection\s+') {
            $insertIndex = $i + 1
            break
        }
    }
    
    if ($insertIndex -ge 0) {
        # Insert after first commented default_selection
        $newContent = @()
        $newContent += $content[0..($insertIndex-1)]
        $newContent += $targetValue
        $newContent += $content[$insertIndex..($content.Count-1)]
        $content = $newContent
        Write-Host "Inserted '$targetValue' after commented default_selection at line $insertIndex"
    } else {
        # No commented default_selection found - add at the end
        $content += $targetValue
        Write-Host "Added '$targetValue' at the end of the file"
    }
}

try {
    Set-Content -LiteralPath $refind -Value $content -Encoding UTF8 -ErrorAction Stop
    Write-Host "Successfully updated: $refind"
} catch {
    Write-Host "Write error: $($_.Exception.Message)"
    return
}