#! /bin/bash

source shared_functions.sh



progress "Verifying internet connection"

if [ ![ ping -c 1 "1.1.1.1" || ping -c 1 "8.8.8.8" ] ]; then
	echo "Couldn't verify internet connection"
	exit 0
fi



progress "Syncing pacman"

pacman -Sy --noconfirm



progress "Configuration" # TODO: dual booting

source config.sh

if [ ![ $auto_partition ] ]; then # Auto-partition not set

	# Need to use UEFI and GPT to allow for easy dual booting with Windows
	read -ersp "\
	\rAuto partitioning is disabled

	\r${lsblk -o NAME,LABEL,FSTYPE,SIZE,MOUNTPOINT}

	\rEnter the drive NAME that you'd like to partition: " drive
	cfdisk $drive

else # TODO: "The resulting partition is not properly aligned for best performance"; probably use sfdisk, as it seems to automatically optimise partitions

	progress "Deleting existing partitions on ${target_drive}, & generating new ones"

	# read -p "\
	# \rWARNING:

	# \rAny data on ${target_drive} will NOT be recoverable!
	# \rProceed? [y/N]: " choice
	# echo -e "\n"

	# if [ "$(to_lower "$choice")" != "y" ]; then
	# 	echo "Abort"
	# 	exit 0
	# fi

	pacman -S --noconfirm parted

	wipefs -a "/dev/$target_drive"

	parted -s "/dev/$target_drive" -- mklabel gpt \
		mkpart BOOT fat32 0 "$boot_size" \
		mkpart ROOT ext4 "$boot_size" "$root_size" \
		mkpart ROOT ext4 "$root_size" 100%



	progress "Formatting partitions"

	mkfs.fat -F32 -n BOOT "/dev/${target_drive}${partition_no_prefix}1"
	mkfs.ext4 -L ROOT "/dev/${target_drive}${partition_no_prefix}2"
	mkfs.ext4 -L HOME "/dev/${target_drive}${partition_no_prefix}3"



	progress "Creating mount point & mounting partitions"

	mount "/dev/${target_drive}${partition_no_prefix}2" /mnt
	mkdir -p /mnt/boot
	mount "/dev/${target_drive}${partition_no_prefix}1" /mnt/boot
	mkdir -p /mnt/home
	mount "/dev/${target_drive}${partition_no_prefix}3" /mnt/home

	echo "Done"



	echo
	lsblk -o NAME,LABEL,FSTYPE,SIZE,MOUNTPOINT /dev/$target_drive
	echo
	read -p "Partitioning & formatting OK? [y/N]: " choice
	echo

	[ "$(to_lower "$choice")" != "y" ] && exit 0

fi



progress "Updating clock"

ln -s /etc/runit/sv/ntpd /run/runit/service/ # https://old.reddit.com/r/artixlinux/comments/xgy3cq/time_not_syncing_using_ntp/
sv up ntpd



progress "Optimising pacage repo mirrors"

# pacman -S --noconfirm reflector
# reflector --country england --latest 10 --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
# Reflector is for Arch... Duh.

pacman -S --noconfirm rankmirrors
rankmirrors "/etc/pacman.d/mirrorlist" # https://linuxcommandlibrary.com/man/rankmirrors/
pacman -Sy --noconfirm



progress "Installing linux kernel & basic apps"

basestrap /mnt base base-devel runit elogind-runit linux linux-firmware



progress "Configuring bootloader"

fstabgen -U /mnt >> /mnt/etc/fstab

echo "Done"



progress "Chrooting into system..."

echo "Run base_install.sh to continue installation"
artix-chroot /mnt ./base_install.sh # Should be able to go straight into the next script, although might need to move everythign into /mnt...