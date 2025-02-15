#!/bin/bash
clear

# Function to select one or more image files
select_img_files() {
    local img_files=(*.img)

    if [ ${#img_files[@]} -eq 0 ]; then
        echo "No .img files found in the current directory."
        return 1
    fi

    echo "Select image file(s) (comma-separated for multiple):"
    for i in "${!img_files[@]}"; do
        echo "$((i+1)). ${img_files[i]}"
    done

    while true; do
        read -p "Enter your selection(s): " choice

        if [[ "$choice" =~ ^[0-9,]+$ ]]; then
            IFS=',' read -ra selections <<< "$choice"
            valid=true
            selected_files=()

            for index in "${selections[@]}"; do
                index=$(echo "$index" | xargs)  # Trim whitespace
                if [[ "$index" -lt 1 || "$index" -gt "${#img_files[@]}" ]]; then
                    valid=false
                    break
                fi
                selected_files+=("${img_files[index-1]}")
            done

            if $valid; then
                echo "You selected: ${selected_files[*]}"
                return 0
            fi
        fi

        echo "Invalid selection. Please enter numbers separated by commas."
    done
}

open() {
    select_img_files
    echo "Debug: Selected file(s) - '${selected_files[*]}'"

    for index in "${!selected_files[@]}"; do
        img_file="${selected_files[$index]}"
        img_file=$(echo "$img_file" | xargs) # Trim whitespace
        vault_name="vault$((index+1))"  # Ensure sequential naming (vault1, vault2, ...)

        # Check if the vault is already open
        if ls /dev/mapper | grep -q "^$vault_name$"; then
            echo "Warning: $vault_name is already open. Skipping..."
            continue
        fi

        mount_point="$(pwd)/$vault_name"

        echo "Debug: Opening LUKS container for $img_file as $vault_name"

        sudo cryptsetup open --type luks "$(pwd)/$img_file" "$vault_name"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to open $img_file"
            continue
        fi

        sudo mkdir -p "$mount_point"
        sudo mount "/dev/mapper/$vault_name" "$mount_point"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to mount $vault_name"
            sudo cryptsetup close "$vault_name"
            continue
        fi

        sudo chmod 777 "$mount_point"
        echo "Vault $vault_name successfully mounted at $mount_point!"
    done

    echo "All selected vaults processed."
    read -p "Press Enter to continue..." # Prevents script from exiting immediately
}


close() {
    echo "Closing all mounted vaults..."
    for vault in $(ls /dev/mapper | grep '^vault'); do
        mount_point="$(pwd)/$vault"

        if mount | grep -q "$mount_point"; then
            echo "Unmounting $mount_point..."
            sync  # Flush writes
            sudo umount "$mount_point" 2>/dev/null
            
            # Check if unmount succeeded
            if mount | grep -q "$mount_point"; then
                echo "Error: Failed to unmount $mount_point. Trying lazy unmount..."
                sudo umount -l "$mount_point"
            fi

            # If it's still mounted, abort closing
            if mount | grep -q "$mount_point"; then
                echo "Error: Unable to unmount $mount_point. It may be in use."
                continue
            fi
        fi

        # Close the LUKS container
        sudo cryptsetup close "$vault"
        rmdir "$mount_point"
        echo "$vault closed."
    done
}


create() {
    read -p "Input container name > " contName
    read -p "Input container size in MB > " contSize
    contName="${contName}.img"

    echo "Creating file..."
    dd if=/dev/urandom of="$contName" bs=1M count="$contSize" status=progress

    echo "Creating LUKS volume..."
    sudo cryptsetup --verify-passphrase luksFormat "$contName"

    echo "Opening LUKS container to make filesystem..."
    sudo cryptsetup open --type luks "$contName" vault_temp
    echo "Formatting..."
    sudo mkfs.ext4 -L vault "/dev/mapper/vault_temp"
    sudo cryptsetup close vault_temp

    echo "Container has been created."
}

clear
echo "1. Open"
echo "2. Close"
echo "3. Create"
echo ""
read -p "Selection > " selection

case $selection in
1) open ;;
2) close ;;
3) create ;;
*) echo "Invalid selection." ;;
esac
