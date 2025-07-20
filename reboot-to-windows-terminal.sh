#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root/sudo user"
    exit 1
fi

cp -f /boot/efi/EFI/refind/PreviousBoot-windows /boot/efi/EFI/refind/vars/PreviousBoot
reboot
