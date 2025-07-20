#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
    sudo_password=$(zenity --password --title="sudo access needed to run")
    echo "$sudo_password" | sudo -S bash "$0" "$@"
    exit
fi

# Twoje polecenia, które wymagają sudo:
cp -f /boot/efi/EFI/refind/PreviousBoot-windows /boot/efi/EFI/refind/vars/PreviousBoot
reboot
