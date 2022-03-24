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
