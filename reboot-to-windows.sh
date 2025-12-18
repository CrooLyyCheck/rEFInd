#!/bin/bash

# Script to change rEFInd default_selection to "Microsoft" (Windows)
# Based on reboot-to-linux-aio.ps1 but simplified for single purpose

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

function print_error() {
    echo -e "${RED}$1${NC}"
}

function print_success() {
    echo -e "${GREEN}$1${NC}"
}

function print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

function print_info() {
    echo -e "${CYAN}$1${NC}"
}

function find_refind_conf() {
    local mount_point="$1"
    local refind_paths=(
        "${mount_point}/EFI/refind/refind.conf"
        "${mount_point}/EFI/BOOT/refind.conf"
    )

    for path in "${refind_paths[@]}"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done

    return 1
}

function set_default_selection_windows() {
    local refind_conf="$1"
    local target_value='default_selection "Microsoft"'

    if [[ ! -f "$refind_conf" ]]; then
        print_error "refind.conf not found: $refind_conf"
        return 1
    fi

    print_info "Found: $refind_conf"

    # Create backup
    cp "$refind_conf" "${refind_conf}.bak" || {
        print_error "Failed to create backup"
        return 1
    }

    # Read file into array
    mapfile -t content < "$refind_conf"

    # Find active (uncommented) default_selection line
    local active_line_index=-1
    local i=0
    for line in "${content[@]}"; do
        if [[ "$line" =~ ^[[:space:]]*default_selection[[:space:]]+ ]]; then
            active_line_index=$i
            break
        fi
        ((i++))
    done

    if [[ $active_line_index -ge 0 ]]; then
        # Active default_selection exists - replace it
        print_info "Found active default_selection at line $((active_line_index + 1)): ${content[$active_line_index]}"
        content[$active_line_index]="$target_value"
        print_success "Replaced with: $target_value"
    else
        # No active default_selection - add it after the first commented one or at the end
        print_info "No active default_selection found. Adding new line."
        
        local insert_index=-1
        i=0
        for line in "${content[@]}"; do
            if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*default_selection[[:space:]]+ ]]; then
                insert_index=$((i + 1))
                break
            fi
            ((i++))
        done
        
        if [[ $insert_index -ge 0 ]]; then
            # Insert after first commented default_selection
            local new_content=()
            new_content+=("${content[@]:0:$insert_index}")
            new_content+=("$target_value")
            new_content+=("${content[@]:$insert_index}")
            content=("${new_content[@]}")
            print_info "Inserted '$target_value' after commented default_selection at line $insert_index"
        else
            # No commented default_selection found - add at the end
            content+=("$target_value")
            print_info "Added '$target_value' at the end of the file"
        fi
    fi

    # Write back to file
    printf '%s\n' "${content[@]}" > "$refind_conf" || {
        print_error "Failed to write to $refind_conf"
        # Restore backup
        mv "${refind_conf}.bak" "$refind_conf"
        return 1
    }

    print_success "Successfully updated: $refind_conf"
    print_info "Backup saved as: ${refind_conf}.bak"
    return 0
}

function main() {
    print_info "=== Reboot to Windows Script ==="
    echo ""

    # Check if running as root, if not, re-execute with sudo
    if [[ $EUID -ne 0 ]]; then
        print_warning "This script requires root privileges."
        print_info "Please enter your password to continue..."
        echo ""
        
        # Re-execute script with sudo, passing all arguments
        exec sudo "$0" "$@"
        exit $?
    fi

    # Find EFI partition mount point
    local efi_mount=""
    
    # Common EFI mount points
    local common_mounts=("/boot/efi" "/efi" "/boot")
    
    for mount in "${common_mounts[@]}"; do
        if [[ -d "${mount}/EFI" ]]; then
            efi_mount="$mount"
            break
        fi
    done

    if [[ -z "$efi_mount" ]]; then
        print_error "Could not find EFI partition. Common mount points checked:"
        for mount in "${common_mounts[@]}"; do
            echo "  - $mount"
        done
        print_warning "\nPlease mount your EFI partition first or specify the mount point as an argument."
        print_info "Usage: $0 [efi_mount_point]"
        exit 1
    fi

    # Allow override via command line argument
    if [[ -n "$1" ]]; then
        efi_mount="$1"
        if [[ ! -d "${efi_mount}/EFI" ]]; then
            print_error "Specified mount point does not contain EFI directory: $efi_mount"
            exit 1
        fi
    fi

    print_success "Found EFI partition at: $efi_mount"
    echo ""

    # Find refind.conf
    local refind_conf
    refind_conf=$(find_refind_conf "$efi_mount")
    
    if [[ $? -ne 0 ]]; then
        print_error "Could not find refind.conf in $efi_mount"
        print_info "Searched locations:"
        echo "  - ${efi_mount}/EFI/refind/refind.conf"
        echo "  - ${efi_mount}/EFI/BOOT/refind.conf"
        exit 1
    fi

    # Set default selection to Windows
    set_default_selection_windows "$refind_conf"
    
    if [[ $? -eq 0 ]]; then
        echo ""
        print_success "Configuration updated successfully!"
        print_info "Windows will be the default boot option on next reboot."
        echo ""
        read -p "Do you want to reboot now? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Rebooting now..."
            reboot
        else
            print_info "Reboot cancelled. Changes will take effect on next reboot."
        fi
    else
        exit 1
    fi
}

main "$@"
