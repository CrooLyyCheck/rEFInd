param(
    [string]$SerialFragment = "0000_0000_0000_0001",
    [char]  $PreferredLetter = 'R',
    [switch]$OpenRefind
)

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

$espGuid = "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}"

$partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction Stop

$esp = $partitions | Where-Object {
    ($_.GptType -eq $espGuid) -or ($_.IsSystem -eq $true) -or ($_.Type -match 'System')
} | Select-Object -First 1

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

$used = (Get-Volume | Where-Object DriveLetter).DriveLetter
$letter = $PreferredLetter

if ($used -contains $letter) {
    $letter = (('R'..'Z') | Where-Object { $used -notcontains $_ } | Select-Object -First 1)
    if (-not $letter) {
        Write-Host "No free drive letter available in range R:..Z:."
        return
    }
    Write-Host "Preferred letter '${PreferredLetter}:' is in use; using '${letter}:' instead."
}

try {
    Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $esp.PartitionNumber -AccessPath "${letter}:" -ErrorAction Stop
    Write-Host "Partition mounted to ${letter}:"
} catch {
    Write-Host "Mount error: $($_.Exception.Message)"
    return
}

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
