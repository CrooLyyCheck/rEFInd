param(
    [char]$PreferredLetter = 'R'
)

# EFI System Partition (ESP) GPT type GUID
$espGuid = "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}"

Write-Host "Scanning disks for EFI partitions containing rEFInd..." -ForegroundColor Cyan

$foundPartitions = @()

# Enumerate all disks and partitions
foreach ($disk in Get-Disk | Where-Object { $_.PartitionStyle -eq 'GPT' -and $_.IsSystem -ne $true }) {
    $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
    if (-not $partitions) { continue }

    foreach ($part in $partitions) {
        # Heuristic: EFI/system-like partition
        $isEsp = ($part.GptType -eq $espGuid) -or ($part.IsSystem -eq $true) -or ($part.Type -match 'System') -or ($part.Size -lt 2GB)
        if (-not $isEsp) { continue }

        # Check if partition is already mounted
        $currentLetter = $null
        if ($part.DriveLetter) {
            $currentLetter = $part.DriveLetter
        }

        # Temporarily mount to a free letter to inspect (only if not already mounted)
        $tempLetter = $null
        $needsUnmount = $false

        if ($currentLetter) {
            # Already mounted, use existing letter
            $tempLetter = $currentLetter
        } else {
            # Find free letter for temporary mount
            for ($c = 90; $c -ge 68; $c--) { # Z..D
                $candidate = [char]$c
                if (-not (Get-Volume -DriveLetter $candidate -ErrorAction SilentlyContinue)) {
                    $tempLetter = $candidate
                    break
                }
            }
            if (-not $tempLetter) { continue }

            try {
                Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AccessPath "${tempLetter}:" -ErrorAction Stop
                $needsUnmount = $true
            } catch {
                continue
            }
        }

        try {
            $refindPath1 = "${tempLetter}:\EFI\refind"
            $refindPath2 = "${tempLetter}:\EFI\BOOT\refind"

            $hasRefind1 = Test-Path $refindPath1 -PathType Container -ErrorAction SilentlyContinue
            $hasRefind2 = Test-Path $refindPath2 -PathType Container -ErrorAction SilentlyContinue

            if ($hasRefind1 -or $hasRefind2) {
                $foundPartitions += [pscustomobject]@{
                    DiskNumber      = $disk.Number
                    DiskName        = if ($disk.FriendlyName) { $disk.FriendlyName } else { "Disk $($disk.Number)" }
                    PartitionNumber = $part.PartitionNumber
                    SizeGB          = [math]::Round($part.Size / 1GB, 2)
                    RefindLocation  = if ($hasRefind1) { "EFI\refind" } else { "EFI\BOOT\refind" }
                    CurrentLetter   = $currentLetter
                    IsCurrentlyMounted = ($null -ne $currentLetter)
                }
            }
        } finally {
            if ($needsUnmount) {
                try {
                    Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AccessPath "${tempLetter}:" -ErrorAction SilentlyContinue
                } catch {}
            }
        }
    }
}

if (-not $foundPartitions) {
    Write-Host "No EFI partitions with rEFInd folder were found." -ForegroundColor Red
    return
}

# Check if any found partition is already mounted
$alreadyMounted = $foundPartitions | Where-Object { $_.IsCurrentlyMounted }
if ($alreadyMounted) {
    Write-Host "Detected disk: $($alreadyMounted[0].DiskName), Partition: $($alreadyMounted[0].PartitionNumber), already mounted as $($alreadyMounted[0].CurrentLetter):" -ForegroundColor Yellow
    Write-Host ""

    do {
        Write-Host "Do you want to unmount it and continue script? [Y/N]" -NoNewline
        $answer = Read-Host " "
        $answer = $answer.Trim()
    } until ($answer -match '^[YyNn]$')

    if ($answer -match '^[Nn]$') {
        Write-Host "Cancelled by user." -ForegroundColor Cyan
        return
    }

    # Unmount all already mounted rEFInd partitions
    foreach ($mounted in $alreadyMounted) {
        try {
            Remove-PartitionAccessPath -DiskNumber $mounted.DiskNumber `
                                      -PartitionNumber $mounted.PartitionNumber `
                                      -AccessPath "$($mounted.CurrentLetter):" -ErrorAction Stop
            Write-Host "Unmounted Disk $($mounted.DiskNumber), Partition $($mounted.PartitionNumber) from $($mounted.CurrentLetter):" -ForegroundColor Green
            # Update the object to reflect unmounted state
            $mounted.IsCurrentlyMounted = $false
            $mounted.CurrentLetter = $null
        } catch {
            Write-Host "Failed to unmount $($mounted.CurrentLetter):: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }
    Write-Host ""
}

Write-Host "Found the following EFI partitions with rEFInd:" -ForegroundColor Green
$index = 1
$foundPartitions | ForEach-Object {
    Write-Host "[$index] $($_.DiskName), Partition: $($_.PartitionNumber), Size: $($_.SizeGB) GB, location: $($_.RefindLocation)" -ForegroundColor Yellow
    $index++
}

# If exactly one, ask for confirmation first
$selected = $null
if ($foundPartitions.Count -eq 1) {
    $p = $foundPartitions[0]
    Write-Host "" 

    $answer = Read-Host "Do you want to mount this partition to drive letter ${PreferredLetter}: ? [Y/N]"
    if ($answer -match '^[Yy]') {
        $selected = $p
    } else {
        Write-Host "User declined automatic choice. Please select one of the found partitions by its number." -ForegroundColor Cyan
    }
}

if (-not $selected) {
    # Ask user to choose from list
    do {
        $raw = Read-Host "Enter partition index to mount (1..$($foundPartitions.Count))"
    } while (-not [int]::TryParse($raw, [ref]$null) -or [int]$raw -lt 1 -or [int]$raw -gt $foundPartitions.Count)

    $selected = $foundPartitions[[int]$raw - 1]
}

# Handle PreferredLetter conflicts
$letter = $PreferredLetter
$existingPartition = Get-Partition -DriveLetter $letter -ErrorAction SilentlyContinue
$existingVolume    = Get-Volume   -DriveLetter $letter -ErrorAction SilentlyContinue

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
        Write-Host "2 - Cancel the script"
        $choice = (Read-Host "Your choice [1/2]").Trim()
    } until ($choice -in @('1','2'))

    if ($choice -eq '2') {
        Write-Host "Cancelled by user." -ForegroundColor Cyan
        return
    }

    try {
        if ($existingPartition) {
            Remove-PartitionAccessPath -DiskNumber $existingPartition.DiskNumber `
                                      -PartitionNumber $existingPartition.PartitionNumber `
                                      -AccessPath "${letter}:" -ErrorAction Stop
        } else {
            Remove-PartitionAccessPath -DriveLetter $letter -AccessPath "${letter}:" -ErrorAction Stop
        }
        Write-Host "Unmounted ${letter}:, continuing..." -ForegroundColor Green
    } catch {
        Write-Host "Unmount error on ${letter}: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
}

# Mount selected partition to PreferredLetter
try {
    Add-PartitionAccessPath -DiskNumber $selected.DiskNumber -PartitionNumber $selected.PartitionNumber -AccessPath "${letter}:" -ErrorAction Stop
    Write-Host "Mounted '$($selected.DiskName)' (Partition $($selected.PartitionNumber)) to ${letter}:" -ForegroundColor Green
    Write-Host "rEFInd is available at: ${letter}:\$($selected.RefindLocation)"
    Write-Host "To unmount: Remove-PartitionAccessPath -DiskNumber $($selected.DiskNumber) -PartitionNumber $($selected.PartitionNumber) -AccessPath ${letter}:"
} catch {
    Write-Host "Mount error: $($_.Exception.Message)" -ForegroundColor Red
}
