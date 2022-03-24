#!/bin/bash -e
MOUNT_POINT="/mnt/diskImage"
SCRIPT_DIR=`dirname $0`

if [ "$EUID" -ne 0 ] 
then 
	echo "Please run as root"
       	exit
fi

if [ -z "$1" ]
then
	echo "No image name provided"
	exit
fi

# Determine the start offset for the first bootable partition
partition_offset=$(parted -s "$1" unit B print | grep -A 2 '^Number' | awk '$1~/1/ {sub(/B$/,"",$2); print $2; exit;}')

# Create a mount point if one doesn't exist
[ ! -d "$MOUNT_POINT" ] && mkdir "$MOUNT_POINT"

# Mount the partition
echo "Mounting '$1' to '$MOUNT_POINT' at offset '$partition_offset'"
mount -o loop,offset=$partition_offset "$1" "$MOUNT_POINT"

if [ -f "$MOUNT_POINT/cmdline.txt" ]
then
	echo "Modifying cmdline.txt"
	sed -i "1 s/$/ consoleblank=0/" "$MOUNT_POINT/cmdline.txt"
fi

if [ -f "$MOUNT_POINT/config.txt" ]
then
	echo "Modifying config.txt"
	sed -i "s/gpu_mem_1024=.*/gpu_mem_1024=256/" "$MOUNT_POINT/config.txt"
	# Moved to rcdash_setup.sh to fix initial reboot issue
	#echo "display_auto_detect=1" >> "$MOUNT_POINT/config.txt"
	echo "ignore_lcd=1" >> "$MOUNT_POINT/config.txt"
	echo "dtoverlay=vc4-kms-dsi-7inch" >> "$MOUNT_POINT/config.txt"
	echo "dtoverlay=vc4-kms-v3d,noaudio" >> "$MOUNT_POINT/config.txt"
fi

if [ -f "$MOUNT_POINT/dietpi.txt" ]
then
	echo "Found dietpi.txt"
	cp "$SCRIPT_DIR/dietpi.txt" "$MOUNT_POINT/dietpi.txt"
	cp "$SCRIPT_DIR/rcdash_setup.sh" "$MOUNT_POINT/Automation_Custom_Script.sh"
else
       	echo "Image is missing dietpi.txt, verify if image is a DietPi image!"
fi

# Unmount image
echo "Unmounting image"
umount "$MOUNT_POINT"
