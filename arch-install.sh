#!/bin/bash
# WARNING: this script will destroy data on the selected disk.

startup() 
{
    clear
    cat << "EOF"

      ___           _       _     _                    _____          _        _ _ _   _             
     / _ \         | |     | |   (_)                  |_   _|        | |      | | | | (_)            
    / /_\ \_ __ ___| |__   | |    _ _ __  _   ___  __   | | _ __  ___| |_ __ _| | | |_ _  ___  _ __  
    |  _  | '__/ __| '_ \  | |   | | '_ \| | | \ \/ /   | || '_ \/ __| __/ _` | | | __| |/ _ \| '_ \ 
    | | | | | | (__| | | | | |___| | | | | |_| |>  <   _| || | | \__ \ || (_| | | | |_| | (_) | | | |
    \_| |_/_|  \___|_| |_| \_____/_|_| |_|\__,_/_/\_\  \___/_| |_|___/\__\__,_|_|_|\__|_|\___/|_| |_|
    
EOF
}

verify_setup()
{
    set -uo pipefail
    trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

    ### Checking internet connection
    wget -q --spider https://www.archlinux.org/
    if [ $? -eq 0 ]; then
        echo "Network is working"
    else
        echo "Please check your network connection"
        exit 1
    fi

    ### Verifying UEFI boot mode
    echo "Verifying UEFI boot mode"
    if [ -d /sys/firmware/efi/efivars ] then
        echo "UEFI boot mode has been verified."
    else
        echo "Please boot into UEFI mode and start the installation again." 
        exit 1
    fi
}

partitioning()
{
    devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
    device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1
    clear

    ### Set up logging ###
    exec 1> >(tee "stdout.log")
    exec 2> >(tee "stderr.log")

    ### Setup the disk and partitions ###
    parted --script "${device}" -- mklabel gpt \
      mkpart ESP fat32 1Mib 129MiB \
      set 1 boot on \
      mkpart primary ext4 129MiB 47683MiB
      mkpart primary ext4 47683MiB 100%

    # Simple globbing was not enough as on one device I needed to match /dev/mmcblk0p1
    # but not /dev/mmcblk0boot1 while being able to match /dev/sda1 on other devices.
    part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
    part_root="$(ls ${device}* | grep -E "^${device}p?2$")"
    part_home="$(ls ${device}* | grep -E "^${device}p?3$")"

    wipefs "${part_boot}"
    wipefs "${part_root}"
    wipefs "${part_home}"

    mkfs.fat -F 32 -n EFIBOOT "${part_boot}"
    mkfs.ext4 -L arch "${part_root}"
    mkfs.ext4 -L home "${part_home}"

    mount "${part_root}" /mnt
    mkdir /mnt/boot
    mount "${part_boot}" /mnt/boot
    mount "${part_home}" /mnt/home
} 

setup()
{

    #Update mirrorlist
    yes | cp -R mirrorlist /etc/pacman.d/mirrorlist

    ### Install and configure the basic system
    pacstrap /mnt base base-devel intel-ucode
    genfstab -Lp /mnt > /mnt/etc/fstab
    cp ./arch-chroot /mnt
    chmod +x /mnt/arch-chroot.sh
    arch-chroot /mnt ./arch-chroot.sh
    
    answer=$(dialog --stdout --inputbox "Installation finished, reboot (y,n)?" 0 0) || exit 1
    clear
    : ${hostname:?"hostname cannot be empty"}
  
    if [ "$answer" == "Y" ] || [ "$answer" == "y" ] || [ "$answer" == "" ]; then
      umount -R /mnt
      reboot
    else
      return 0
    fi
}

startup
verify_setup
partitioning
setup






