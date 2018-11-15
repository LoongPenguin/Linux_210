#! /bin/sh

mount -t vfat /dev/mmcblk1p1 /mnt/ || { echo "can not mount tfcard"; exit 0; }
ls /mnt || { echo "can not list files"; exit 0; }
umount /mnt || { echo "can not umount tfcard"; exit 0; }
