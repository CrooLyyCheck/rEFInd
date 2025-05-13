# --- Find disk by partial or full serial number ---
$serial = "0000_0000_0000_0001" # put in "" your partial or full serial number of disk with installed rEFInd
$disk = Get-Disk | Where-Object { $_.SerialNumber -match "$serial" }

if ($disk) {
    # --- Find EFI-like partitions ---
    $efi = Get-Partition -DiskNumber $disk.Number | 
           Where-Object { 
               $_.Size -lt 2GB -and 
               (Get-Volume -Partition $_).FileSystem -eq 'FAT32'
           } | 
           Select-Object -ExpandProperty PartitionNumber

    if ($efi) {
        Write-Host "Found EFI partition number: $efi on disk number: $($disk.Number)"
        
        # --- Mount to R: ---
        try {
            Get-Partition -DiskNumber $disk.Number -PartitionNumber $efi | 
                Remove-PartitionAccessPath -AccessPath "R:" -ErrorAction SilentlyContinue
            
            Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $efi -AccessPath "R:"
            Write-Host "Partition mounted to R:"
            
        } catch {
            Write-Host "Error: $_"
        }
    } else {
        Write-Host "No qualifying partition found on disk $($disk.Number)"
    }
} else {
    Write-Host "No disk found with serial fragment: $serial"
}