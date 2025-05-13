# rEFInd
A collection of scripts to simplify rebooting into a specific operating system from another OS booted instance. Particularly useful for dual-boot/multi-boot environments and remotely managed systems.

Before you start:
- Don't run any scripts without knowing what they do.
- Edit serial disk variable and path for $sourcefile
- You must prepare "PreviousBoot" files by just simply boot into Every desired OS and for each boot copy PreviousBoot somewhere on rEFInd folder for ex.: PreviousBoot-linux, PreviousBoot-windows, PreviousBoot-freebsd (can be at same level of refind.conf).
- For mounting rEFInd partiton in windows there is two options:
    Use command mountvol *DISK LETTER*: /S ex.: mountvol U: /S
    Run file in repo called mount-efi.ps1 (AGAIN: NEED TO EDIT DISK SERIAL NUMBER AND PATH IN SCRIPT TO WORK ON YOUR SYSTEM.)
    
For easy and quick access in windows to lauching ps1 script you can make new windows shortcut with "Run as Administrator" mark checked and something like: powershell.exe -ExecutionPolicy Bypass -File "%USERPROFILE%\reboot-to-linux.ps1" -Verb RunAs

Requirements for *.ps1 files:
- Powershell compatible windows (for now) if you need for older windows make new issue requesting compability.
- Administrative rights to run scripts as Admin.

Requirements for *.sh file:

- Yhm... Just linux with bash and root/sudo/wheel access
