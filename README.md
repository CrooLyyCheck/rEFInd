# rEFInd
A collection of scripts to simplify rebooting into a specific operating system from another OS booted instance. Particularly useful for dual-boot/multi-boot environments and remotely managed systems.

Requirements for *.ps1 files:
- Prepared "PreviousBoot" files by just simply boot into Every desired OS and for each boot copy PreviousBoot somewhere on rEFInd folder for ex.: PreviousBoot-linux, PreviousBoot-windows, PreviousBoot-freebsd (can be at same level of refind.conf). For mounting rEFInd partiton in windows there is file in repo called mount-efi.ps1 (NEED TO EDIT SERIAL NUMBER IN SCRIPT TO WORK ON YOUR SYSTEM.)
- Powershell compatible windows (for now) if you need for older windows make new issue requesting compability.
- Administrative rights to run scripts as Admin.

Requirements for *.sh file:
- Prepared "PreviousBoot" files by just simply boot into Every desired OS and for each boot copy PreviousBoot somewhere on rEFInd folder for ex.: PreviousBoot-linux, PreviousBoot-windows, PreviousBoot-freebsd (can be at same level of refind.conf). For mounting rEFInd partiton in windows there is file in repo called mount-efi.ps1 (NEED TO EDIT SERIAL NUMBER IN SCRIPT TO WORK ON YOUR SYSTEM.)
- Yhm... Just linux with bash

For .sh files you can just copy 2 commands instead running script. (Compared to 56 lines of powershell for windows XD its not worth)
