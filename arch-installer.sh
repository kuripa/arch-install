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

check_script()
{
    set -uo pipefail
    trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR
}

check_boot_system()
{
    echo "Verifying UEFI boot mode"
    if [ -d /sys/firmware/efi/efivars ]; then
        echo "UEFI boot mode has been verified."
    else
        echo "Please boot into UEFI mode and start the installation again."
        exit 1
    fi
}

check_connection()
{
    wget -q --spider https://www.archlinux.org/
    if [ $? -eq 0 ]; then
        echo "Network is working"
    else
        echo "Please check your network connection"
        exit 1
    fi
}

create_partition()
{
    devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
    device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1
    clear
    
    ### Open cgdisk with selected device
    cgdisk "${device}"
    
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
    
    if [ -d /mnt/boot ]; then
        mount "${part_boot}" /mnt/boot
    else
        mkdir /mnt/boot
        mount "${part_boot}" /mnt/boot
    fi
    
    if [ -d /mnt/home ]; then
        mount "${part_home}" /mnt/home
    else
        mkdir /mnt/home
        mount "${part_home}" /mnt/home
    fi
}

umount_drives()
{
    umount -R /mnt/boot && umount /mnt/home && umount /mnt
}

create_user()
{    
    username=$(dialog --stdout --title "Username" --inputbox "Enter username" 0 0) || exit 1
    clear
    : ${username:?"user cannot be empty"}
    
    password=$(dialog --stdout --title "User password" --passwordbox "Enter password for user $username" 0 0) || exit 1
    clear
    : ${password:?"password cannot be empty"}
    
    password2=$(dialog --stdout --title "User password" --passwordbox "Enter password again for user $username" 0 0) || exit 1
    clear
    [[ "$password" == "$password2" ]] || ( echo "Passwords did not match"; exit 1; )
    
    arch-chroot /mnt useradd -m -g users -G wheel,storage,power,video,audio,games,input -s /bin/bash "$user"
    
    echo "$username:$password" | chpasswd /mnt
    
    sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g' /mnt/etc/sudoers
    sed -i 's/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/g' /mnt/etc/sudoers
}

create_root_password() 
{
    password_root=$(dialog --stdout --title "Root password" --passwordbox "Enter new root password" 0 0) || exit 1
    clear
    : ${password_root:?"password cannot be empty"}
    
    password2_root=$(dialog --stdout --title "Root password" --passwordbox "Enter root password again" 0 0) || exit 1
    clear
    [[ "$password_root" == "$password2_root" ]] || ( echo "Passwords did not match"; exit 1; )

    echo "root:$password_root" | chpasswd /mnt
}

set_hostname()
{
    hostname=$(dialog --stdout --title "Hostname" --inputbox "Enter hostname" 0 0) || exit 1
    clear
    : ${hostname:?"hostname cannot be empty"}

    echo "${hostname}" > /mnt/etc/hostname
}

set_timezone()
{
    ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
    hwclock --systohc
}

configure_locale()
{
    old_us="\#en_US.UTF-8 UTF-8"
    new_us="en_US.UTF-8 UTF-8"
    old_de="\#de_DE.UTF-8 UTF-8"
    new_de="de_DE.UTF-8 UTF-8"
    location="/etc/locale.gen"
    sed -i "s/$old_us/$new_us/" $location
    sed -i "s/$old_de/$new_de/" $location
    locale-gen
    echo "LANG=en_US.UTF­8" > "/etc/locale.conf"
    echo "LANG=de_DE.UTF­8" > "/etc/locale.conf"
}

configure_mirrorlist()
{
    url="https://www.archlinux.org/mirrorlist/?country=DE&protocol=http&protocol=https&ip_version=4&ip_version=6"
    tmpfile=$(mktemp --suffix=-mirrorlist)
    curl -so ${tmpfile} ${url}
    sed -i 's/^#Server/Server/g' ${tmpfile}

    if [[ -s ${tmpfile} ]]; then
        { echo " Backing up the original mirrorlist..."
        mv -i /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.orig; } &&
        { echo " Rotating the new list into place..."
        mv -i ${tmpfile} /etc/pacman.d/mirrorlist; }
    else
        echo " Unable to update, could not download list."
    fi
  
    pacman -Sy pacman-contrib
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.tmp
    rankmirrors /etc/pacman.d/mirrorlist.tmp > /etc/pacman.d/mirrorlist
    rm /etc/pacman.d/mirrorlist.tmp
}

install_base_system()
{ 
    pacman -Sy archlinux-keyring
    pacstrap /mnt base base-devel intel-ucode 
    genfstab -Lp /mnt > /mnt/etc/fstab
}

install_bootloader()
{
    arch-chroot /mnt bootctl install
    
cat <<EOF > /mnt/boot/loader/loader.conf
default arch
EOF
    
cat <<EOF > /mnt/boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=PARTUUID=$(blkid -s PARTUUID -o value "$part_root") rw
EOF
}

configure_mkinitcpio()
{
    arch-chroot /mnt mkinitcpio -p linux
}

reboot_system()
{
    answer=$(dialog --stdout --title Installation finished --yesno "Installation finished, reboot?" 0 0) || exit 1
    clear
    
    if [ "$answer" -eq 0 ]; then
        umount_drives
        reboot
    else
        return 0
    fi
}

check_script
check_boot_system
check_boot_system
create_partition
configure_mirrorlist
install_base_system
set_hostname
set_timezone
configure_locale
create_user
create_root_password
install_bootloader
configure_mkinitcpio
reboot_system
