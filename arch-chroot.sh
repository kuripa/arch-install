#!/bin/bash

configure_user()
{
    ### Get infomation from user
    hostname=$(dialog --stdout --title "Hostname" --inputbox "Enter hostname" 0 0) || exit 1
    clear
    : ${hostname:?"hostname cannot be empty"}
    
    password_root=$(dialog --stdout --title "Root password" --passwordbox "Enter new root password" 0 0) || exit 1
    clear
    : ${password_root:?"password cannot be empty"}
    
    password2_root=$(dialog --stdout --title "Root password" --passwordbox "Enter root password again" 0 0) || exit 1
    clear
    [[ "$password_root" == "$password2_root" ]] || ( echo "Passwords did not match"; exit 1; )
    
    username=$(dialog --stdout --title "Username" --inputbox "Enter username" 0 0) || exit 1
    clear
    : ${username:?"user cannot be empty"}
    
    password=$(dialog --stdout --title "User password" --passwordbox "Enter password for user $username" 0 0) || exit 1
    clear
    : ${password:?"password cannot be empty"}
    
    password2=$(dialog --stdout --title "User password" --passwordbox "Enter password again for user $username" 0 0) || exit 1
    clear
    [[ "$password" == "$password2" ]] || ( echo "Passwords did not match"; exit 1; )
    
    echo "${hostname}" > /etc/hostname
    
    useradd -m -g users -G wheel,storage,power,video,audio,games,input -s /bin/bash "$user"
    
    echo "$username:$password" | chpasswd --root
    echo "root:$password_root" | chpasswd --root
    
    sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g' /etc/sudoers
    sed -i 's/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/g' /etc/sudoers
}

setup_locale()
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

setup_timezone()
{
    ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
    hwclock --systohc
}

configure_bootloader()
{
    ### Bootloader installation
    bootctl install
    
    cat <<EOF > /boot/loader/loader.conf
    default arch
EOF
    
    cat <<EOF > /boot/loader/entries/arch.conf
    title   Arch Linux
    linux   /vmlinuz-linux
    initrd  /intel-ucode.img
    initrd  /initramfs-linux.img
    options root=PARTUUID=$(blkid -s PARTUUID -o value "$part_root") rw
EOF
    
    mkinitcpio -p linux
    
}

install_essential_packages()
{
    pacman -S git vim ntfs-3g bash-completion ufw --noconfirm
    pacman -S unzip unrar p7zip p7zip-plugins unrar tar rsync --noconfirm
}

configure_user
setup_locale
setup_timezone
configure_bootloader
install_essential_packages

