# rEFInd Boot Manager Scripts

A collection of scripts for managing the rEFInd boot loader to simplify rebooting into specific operating systems from another booted OS instance. Particularly useful for dual-boot/multi-boot environments and remotely managed systems without the ability to choose boot entry over the network.

## ⚠️ Before You Start

- Don't run any scripts without knowing what they do
- Always review script contents before execution
- Make sure you have proper backups of your EFI configuration

## Available Scripts

### Windows to Linux: `reboot-to-linux-aio.ps1`

An all-in-one PowerShell script for Windows users that provides an interactive menu to manage rEFInd boot configuration.

**Features:**
- Automatic detection of EFI partitions with rEFInd
- Safe partition mounting with user consent
- Sets Linux (vmlinuz) as default boot option
- Interactive menu with multiple options
- Automatic backup creation before config changes

**Menu Options:**
1. Detect and mount rEFInd partition
2. Set Linux as default for next reboot
3. Reboot computer now
4. Run all steps automatically (A)
5. Quit (Q)

**Requirements:**
- Windows with PowerShell
- Administrative rights to run as Administrator
- rEFInd boot manager installed on EFI partition

**Usage:**
```powershell
# Run with default settings (mounts to R: drive)
.\reboot-to-linux-aio.ps1

# Specify custom drive letter
.\reboot-to-linux-aio.ps1 -PreferredLetter X
```

### Linux to Windows: `reboot-to-windows.sh`

A bash script for Linux users to set Windows as the default boot option in rEFInd.

**Features:**
- Automatically finds EFI partition mount point
- Sets Windows (Microsoft) as default boot option
- Creates automatic backup before changes
- Colored output for better readability
- Optional immediate reboot

**Requirements:**
- Linux with bash shell
- Root/sudo access
- rEFInd boot manager installed on EFI partition
- EFI partition mounted (usually at /boot/efi)

**Usage:**
```bash
# Make script executable
sudo chmod +x reboot-to-windows.sh

# Run with automatic EFI detection
sudo ./reboot-to-windows.sh

# Or specify EFI mount point manually
sudo ./reboot-to-windows.sh /boot/efi
```

## How It Works

### Windows → Linux Workflow

1. **Detection Phase**: Script scans for EFI partitions with official ESP GUID
2. **Mount Phase**: Mounts selected partition to specified drive letter (default: R:)
3. **Configuration**: Updates `refind.conf` to set `default_selection "vmlinuz"`
4. **Reboot**: Optionally reboots immediately into Linux

### Linux → Windows Workflow

1. **Detection Phase**: Finds EFI partition at common mount points (/boot/efi, /efi, /boot)
2. **Backup**: Creates backup of existing refind.conf
3. **Configuration**: Updates `refind.conf` to set `default_selection "Microsoft"`
4. **Reboot**: Optionally reboots immediately into Windows

## Safety Features

### For Windows Script
- Only accesses partitions with official EFI System Partition GUID
- Excludes Windows system disk entirely
- Uses temporary mount points for scanning (not permanent drive letters)
- Requires explicit user consent before mounting partitions
- Asks confirmation before unmounting existing drives

### For Linux Script
- Automatically requests sudo if not running as root
- Creates backup before modifying configuration
- Validates file read/write permissions
- Provides detailed error messages
- Asks confirmation before rebooting

## Configuration Files

Both scripts modify the `refind.conf` file located in:
- `/EFI/refind/refind.conf`
- `/EFI/BOOT/refind.conf`

The scripts search both locations automatically.

## Troubleshooting

### Windows Script Issues

**"No EFI partitions with rEFInd folder were found"**
- Ensure rEFInd is properly installed
- Check if EFI partition is on a different disk
- Verify partition has official ESP GUID

**"Drive letter is already in use"**
- Script will ask if you want to unmount it
- Choose 'Y' to proceed or 'N' to cancel
- Consider using different letter with `-PreferredLetter` parameter

### Linux Script Issues

**"Could not find EFI partition"**
- Check if EFI partition is mounted: `mount | grep efi`
- Mount manually: `sudo mount /dev/sdXN /boot/efi`
- Specify mount point as argument to script

**"Permission denied"**
- Always run with sudo: `sudo ./reboot-to-windows.sh`
- Check if EFI partition is mounted read-only

**"Could not find refind.conf"**
- Verify rEFInd installation: `ls /boot/efi/EFI/refind/`
- Check alternative location: `ls /boot/efi/EFI/BOOT/`

## Contributing

Feel free to submit issues or pull requests if you find bugs or have suggestions for improvements.

## License

These scripts are provided as-is for managing rEFInd boot configurations. Use at your own risk and always maintain backups of your EFI configuration.