#! /bin/sh

mount -t vfat /dev/sda1 /mnt/ || { echo "can not mount udisk"; exit 0; }
ls /mnt || { echo "can not list files"; exit 0; }
umount /mnt || { echo "can not umount udisk"; exit 0; }


