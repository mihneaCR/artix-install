#!/bin/bash
#
loadkeys us
read -r -p "Enter drive to partition: " drive
fdisk -l /dev/"$drive" | grep model
read -r -p "Are you sure? [y/N] " response
response=${response,,} # tolower
if [[ "$response" =~ ^(no|n)$ ]]; then
	exit 0
fi
# Create 1GB EFI Partition, and another partition filling up the remaining space
(
	echo d
	echo
	echo d
	echo
	echo g
	echo n
	echo
	echo
	echo +1G
	echo t
	echo
	echo 1
	echo n
	echo
	echo
	echo
	echo w
) | fdisk /dev/"$drive"
read -r -p "Press enter to continue"

rc-service ntpd start
pacman -Syy

cryptsetup luksFormat /dev/"$drive"p2
cryptsetup open /dev/"$drive"p2 cryptroot
# Format partitions
mkfs.fat -F 32 /dev/"$drive"p1
mkfs.btrfs -L artix-root /dev/mapper/cryptroot

uuid=$(lsblk -o UUID /dev/mapper/cryptroot | grep -v UUID)
boot_uuid=$(lsblk -o UUID /dev/"$drive"p1 | grep -v UUID)

mount UUID="$uuid" /mnt
btrfs su cr /mnt/@
btrfs su cr /mnt/@/home
btrfs su cr /mnt/@/.snapshots
mkdir /mnt/@/.snapshots/1
btrfs su cr /mnt/@/.snapshots/1/snapshot
mkdir /mnt/@/boot
btrfs su cr /mnt/@/boot/grub
btrfs su cr /mnt/@/opt
btrfs su cr /mnt/@/root
btrfs su cr /mnt/@/srv
btrfs su cr /mnt/@/tmp
mkdir /mnt/@/usr
btrfs su cr /mnt/@/usr/local
mkdir /mnt/@/var
btrfs su cr /mnt/@/var/cache
btrfs su cr /mnt/@/var/log
btrfs su cr /mnt/@/var/spool
btrfs su cr /mnt/@/var/tmp
#SWAP
btrfs su cr /mnt/@/swap
btrfs subvolume list /mnt

read -r -p "Press enter to continue"

curr_date=$(date +"%Y-%m-%d %H:%M:%S")
cat <<EOF >>/mnt/@/.snapshots/1/info.xml
<?xml version="1.0"?>
<snapshot>
	<type>single</type>
	<num>1</num>
	<date>$curr_date</date>
	<description>First root filesystem, created at installation</description>
</snapshot>
EOF

read -r -p "Press enter to continue"
btrfs su set-default "$(btrfs su list /mnt | grep "@/.snapshots/1/snapshot" | grep -oP '(?<=ID )[0-9]+')" /mnt
btrfs quota enable /mnt/
btrfs qgroup create 1/0 /mnt/
chattr +C /mnt/@/var/cache
chattr +C /mnt/@/var/log
chattr +C /mnt/@/var/spool
chattr +C /mnt/@/var/tmp
umount /mnt/
mount UUID="$uuid" -o compress=zstd /mnt

# Creating necessary dirs
mkdir /mnt/.snapshots
mkdir -p /mnt/boot/grub
mkdir -p /mnt/opt
mkdir -p /mnt/root
mkdir -p /mnt/srv
mkdir -p /mnt/tmp
mkdir -p /mnt/usr/local
mkdir -p /mnt/var/cache
mkdir -p /mnt/var/log
mkdir -p /mnt/var/spool
mkdir -p /mnt/var/tmp
mkdir /mnt/efi
mkdir /mnt/home
mkdir /mnt/swap

# Display layout

pacman --noconfirm -S tree
tree -L 3 /mnt/
read -r -p "Layout created, continue?"

# Partition mounting
mount UUID="$uuid" -o compress=zstd,subvol=@/.snapshots /mnt/.snapshots
mount UUID="$uuid" -o compress=zstd,subvol=@/boot/grub/ /mnt/boot/grub
mount UUID="$uuid" -o compress=zstd,subvol=@/opt /mnt/opt
mount UUID="$uuid" -o compress=zstd,subvol=@/root /mnt/root
mount UUID="$uuid" -o compress=zstd,subvol=@/srv /mnt/srv
mount UUID="$uuid" -o compress=zstd,subvol=@/tmp /mnt/tmp
mount UUID="$uuid" -o compress=zstd,subvol=@/usr/local /mnt/usr/local
mount UUID="$uuid" -o compress=zstd,subvol=@/var/cache /mnt/var/cache
mount UUID="$uuid" -o compress=zstd,subvol=@/var/spool /mnt/var/spool
mount UUID="$uuid" -o compress=zstd,subvol=@/var/tmp /mnt/var/tmp
mount UUID="$boot_uuid" /mnt/efi
mount UUID="$uuid" -o compress=zstd,subvol=@/home /mnt/home
mount UUID="$uuid" -o compress=zstd,subvol=@/swap /mnt/swap
btrfs filesystem mkswapfile --size 8g --uuid clear /mnt/swap/swapfile
swapon /mnt/swap/swapfile

read -r -p "Swap creation successful?"
# Determine CPU vendor
cpu_vendor=$(grep 'vendor' /proc/cpuinfo | uniq | cut -d' ' -f2-)
if [[ "$cpu_vendor" == "AuthenticAMD" ]]; then
	ucode_package="amd-ucode"
elif [[ "$cpu_vendor" == "GenuineIntel" ]]; then
	ucode_package="intel-ucode"
fi

# System installation
basestrap /mnt base base-devel openrc elogind-openrc linux linux-firmware linux-headers "$ucode_package" btrfs-progs doas vim

# General utilities
basestrap /mnt man-db man-pages texinfo zsh
# Artix services
basestrap /mnt cronie cronie-openrc networkmanager networkmanager-openrc networkmanager-openvpn network-manager-applet ntp ntp-openrc acpid acpid-openrc syslog-ng syslog-ng-openrc

# Artix recommended utilities:
basestrap /mnt dosfstools freetype2 ntfs-3g fuse2 gptfdisk mtools device-mapper-openrc cryptsetup-openrc

#generate fstab
fstabgen -U /mnt >>/mnt/etc/fstab
#remove:
subvolid_rm=$(btrfs subvolume list /mnt | grep '@/.snapshots/1/snapshot' | cut -d' ' -f2)
sed -i "s/\,subvolid=$subvolid_rm\,subvol=\/@\/\.snapshots\/1\/snapshot//" /mnt/etc/fstab

# vim /mnt/etc/fstab

# Remove rootflags=subvol=${rootsubvol} from both files
#vim /mnt/etc/grub.d/10_linux
#vim /mnt/etc/grub.d/20_linux_xen

echo "/swap/swapfile	none	swap	defaults	0 0" >>/etc/fstab/
less /mnt/etc/fstab
cp next-install.sh /mnt/root/
artix-chroot /mnt
