param(
    [char]$PreferredLetter = 'R'
)

# EFI System Partition (ESP) GPT type GUID
$espGuid = "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}"

Write-Host "Scanning disks for EFI partitions containing rEFInd..." -ForegroundColor Cyan
Write-Host ""
Write-Host "This script needs to temporarily access EFI partitions to check for rEFInd." -ForegroundColor Yellow
Write-Host "Partitions will be mounted to temporary folders (not drive letters) for inspection." -ForegroundColor Yellow
Write-Host "Only partitions with official EFI System Partition GUID will be checked." -ForegroundColor Yellow
Write-Host ""

do {
    Write-Host "Do you want to proceed with partition inspection? [Y/N]" -NoNewline
    $scanConsent = Read-Host " "
    $scanConsent = $scanConsent.Trim()
} until ($scanConsent -match '^[YyNn]$')

if ($scanConsent -match '^[Nn]$') {
    Write-Host "Operation cancelled by user. No partitions were accessed." -ForegroundColor Cyan
    return
}

Write-Host ""
Write-Host "Starting scan..." -ForegroundColor Green

$foundPartitions = @()
$tempBasePath = Join-Path $env:TEMP "rEFInd_Scan"

# Create base temp directory if it doesn't exist
if (-not (Test-Path $tempBasePath)) {
    try {
        New-Item -Path $tempBasePath -ItemType Directory -Force | Out-Null
    } catch {
        Write-Host "Failed to create temporary directory: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
}

# Enumerate all disks and partitions
# Exclude system disk to be extra safe
foreach ($disk in Get-Disk | Where-Object { $_.PartitionStyle -eq 'GPT' -and $_.IsSystem -ne $true -and $_.IsBoot -ne $true }) {
    $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
    if (-not $partitions) { continue }

    foreach ($part in $partitions) {
        # STRICT: Only check partitions with official EFI System Partition GUID
        # This is the ONLY reliable way to identify true EFI partitions
        if ($part.GptType -ne $espGuid) { 
            continue 
        }

        # Additional safety: Skip if this is a boot partition (Windows system ESP)
        if ($part.IsBoot -eq $true) {
            continue
        }

        # Check if partition is already mounted
        $currentLetter = $null
        if ($part.DriveLetter) {
            $currentLetter = $part.DriveLetter
        }

        # Use mount point instead of drive letter for temporary access
        $tempMountPoint = $null
        $needsUnmount = $false
        $accessPath = $null

        if ($currentLetter) {
            # Already mounted, use existing letter
            $accessPath = "${currentLetter}:"
        } else {
            # Create temporary mount point folder
            $tempMountPoint = Join-Path $tempBasePath "Disk$($disk.Number)_Part$($part.PartitionNumber)"
            
            try {
                # Create mount point directory
                if (-not (Test-Path $tempMountPoint)) {
                    New-Item -Path $tempMountPoint -ItemType Directory -Force | Out-Null
                }
                
                # Mount partition to the folder
                Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AccessPath $tempMountPoint -ErrorAction Stop
                $needsUnmount = $true
                $accessPath = $tempMountPoint
            } catch {
                # Clean up folder if mount failed
                if (Test-Path $tempMountPoint) {
                    Remove-Item $tempMountPoint -Force -ErrorAction SilentlyContinue
                }
                continue
            }
        }

        try {
            # Verify this looks like an EFI partition by checking for EFI folder
            $efiFolder = Join-Path $accessPath "EFI"
            if (-not (Test-Path $efiFolder -PathType Container -ErrorAction SilentlyContinue)) {
                # Not an EFI partition (no EFI folder), skip it
                continue
            }

            $refindPath1 = Join-Path $accessPath "EFI\refind"
            $refindPath2 = Join-Path $accessPath "EFI\BOOT\refind"

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
                    Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AccessPath $tempMountPoint -ErrorAction SilentlyContinue
                    # Clean up the mount point folder
                    if (Test-Path $tempMountPoint) {
                        Remove-Item $tempMountPoint -Force -ErrorAction SilentlyContinue
                    }
                } catch {}
            }
        }
    }
}

# Clean up base temp directory
if (Test-Path $tempBasePath) {
    Remove-Item $tempBasePath -Force -Recurse -ErrorAction SilentlyContinue
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

    Write-Host "" 
    do {
        Write-Host "Do you want to unmount ${letter}: and continue? [Y/N]" -NoNewline
        $unmountAnswer = Read-Host " "
        $unmountAnswer = $unmountAnswer.Trim()
    } until ($unmountAnswer -match '^[YyNn]$')

    if ($unmountAnswer -match '^[Nn]$') {
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