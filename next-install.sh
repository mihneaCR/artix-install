#!/bin/bash
#
confirm() {
	# call with a prompt string or use a default
	read -r -p "${1:-Are you sure? [y/N]} " response
	case "$response" in
	[yY][eE][sS] | [yY])
		true
		;;
	*)
		false
		;;
	esac
}
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >>/etc/locale.gen
locale-gen
printf 'export LANG="en_US.UTF-8"\nexport LC_COLLATE="C"' >>/etc/locale.conf

read -r -p "Hostname: " local_hostname
read -r -p "Local domain: " local_domain

cat <<EOF >>/etc/hosts
127.0.0.1 localhost
::1 localhost
127.0.1.1 $local_hostname.$local_domain $local_hostname
EOF
# Add encrypt hook
sed -i 's/consolefont block/consolefont block encrypt/g' /etc/mkinitcpio.conf
mkinitcpio -P

# Enable arch repos for Artix
pacman -S --noconfirm artix-archlinux-support
cat <<EOF >>/etc/pacman.conf
# Arch Repos
[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF
pacman-key --populate archlinux
pacman -Syu
# snap-pac and grub-btrfs not available in artix repos
pacman -S --noconfirm --needed grub efibootmgr snapper snap-pac grub-btrfs

umount /.snapshots
rm -r /.snapshots
btrfs subvolume list /
snapper --no-dbus -c root create-config /
btrfs subvolume delete /.snapshots
btrfs subvolume list /
mkdir /.snapshots
mount -a
chmod 750 /.snapshots

# Install GRUB
# Confirm correct partition for UUID first
fdisk -l | less
read -r -p "Enter drive : " drive
fdisk -l /dev/"$drive" | grep model
confirm "Is this the correct drive?" && partition_uuid=$(ls -l /dev/disk/by-uuid/ | grep "$partition_uuid"2 | cut -d' ' -f9)

# Perform necessary GRUB Configuration
additional_kparams="cryptdevice=UUID=$partition_uuid:cryptroot:allow-discards"
sed -i 's/ part_msdos//g' /etc/default/grub
sed -i 's/#GRUB_ENABLE_CRYPTODISK/GRUB_ENABLE_CRYPTODISK/g' /etc/default/grub
sed -i "s/LINUX_DEFAULT=\"/LINUX_DEFAULT=\"$additional_kparams /g" /etc/default/grub
confirm "Detect other operating systems?" && pacman -S --needed os-prober && sed -i 's/OS_PROBER=false/OS_PROBER=true/g' /etc/default/grub
echo "OS-prober setup, mount Windows EFI and run mkconfig again to enable booting Windows!"

grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=Artix-GRUB --removable \
	--modules="normal test efi_gop efi_uga search echo linux all_video gfxmenu gfxterm_background gfxterm_menu gfxterm loadenv configfile gzio part_gpt btrfs"

# Generate Grub CFG
grub-mkconfig -o /boot/grub/grub.cfg
read -r -p "GRUB configured, press enter to continue!"

# Services

rc-update add device-mapper boot
rc-update add dmcrypt boot

rc-update add dbus default
rc-update add elogind boot

rc-update add NetworkManager default
rc-update add cronie default
rc-update add ntpd default
rc-update add acpid default
rc-update add syslog-ng default

# set root user pw
read -r -p "Set root password"
passwd
read -r -p "Create your user account: " local_username
echo "Your user is: " "$local_username"
read -r -p "Continue?"
groupadd plugdev
useradd -m -G wheel,plugdev -s /usr/bin/zsh "$local_username"
# Doas config
touch /etc/doas.conf
chown -c root:root /etc/doas.conf
chmod -c 0400 /etc/doas.conf
#check for errors
cat <<EOF >>/etc/doas.conf
permit setenv {PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin} :wheel
permit nopass :wheel cmd reboot
permit nopass :wheel cmd poweroff
permit nopass :wheel cmd /usr/bin/mount.nfs
permit nopass :wheel cmd tlp args fullcharge
permit nopass :plugdev as root cmd /usr/bin/smartctl
permit persist $local_username

EOF
doas -C /etc/doas.conf && echo "config ok" || echo "config error"

# Install yay
confirm "Install yay?" && pacman -S --needed git base-devel && git clone https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg -si

exit
