#!/bin/sh
#
# Description	: Build Qt Script.
# Authors		: jianjun jiang - jerryjianjun@gmail.com
# Version		: 0.01
# Notes			: None
#

CPU_NUM=$(cat /proc/cpuinfo |grep processor|wc -l)
CPU_NUM=$((CPU_NUM+1))

SOURCE_DIR=$(cd `dirname $0` ; pwd)

RELEASE_DIR=${SOURCE_DIR}/release/
BOOTLOADER_XBOOT_CONFIG=arm32-x210ii
QT_KERNEL_CONFIG=x210ii_qt_defconfig
INITRD_KERNEL_CONFIG=x210ii_initrd_defconfig
BUILDROOT_CONFIG=x210ii_defconfig

setup_environment()
{
	cd ${SOURCE_DIR};
	mkdir -p ${RELEASE_DIR} || return 1;
}

build_bootloader_xboot()
{
	if [ ! -f ${RELEASE_DIR}/zImage-initrd ]; then
		echo "not found kernel zImage-initrd, please build kernel first" >&2
		return 1
	fi

	if [ ! -f ${RELEASE_DIR}/zImage-qt ]; then
		echo "not found kernel zImage-qt, please build kernel first" >&2
		return 1
	fi

	# copy zImage-initrd and zImage-qt to xboot's romdisk directory
	cp -v ${RELEASE_DIR}/zImage-initrd ${SOURCE_DIR}/xboot/src/arch/arm32/mach-x210ii/romdisk/boot || return 1;
	cp -v ${RELEASE_DIR}/zImage-qt ${SOURCE_DIR}/xboot/src/arch/arm32/mach-x210ii/romdisk/boot || return 1;

	# compiler xboot
	cd ${SOURCE_DIR}/xboot || return 1
	make TARGET=${BOOTLOADER_XBOOT_CONFIG} CROSS=/usr/local/arm/arm-2012.09/bin/arm-none-eabi- clean || return 1;
	make TARGET=${BOOTLOADER_XBOOT_CONFIG} CROSS=/usr/local/arm/arm-2012.09/bin/arm-none-eabi- || return 1;

	# rm zImage-initrd and zImage-qt
	rm -fr ${SOURCE_DIR}/xboot/src/arch/arm32/mach-x210ii/romdisk/boot/zImage-initrd
	rm -fr ${SOURCE_DIR}/xboot/src/arch/arm32/mach-x210ii/romdisk/boot/zImage-qt

	# copy xboot.bin to release directory
	cp -v ${SOURCE_DIR}/xboot/output/xboot.bin ${RELEASE_DIR}

	echo "" >&2
	echo "^_^ xboot path: ${RELEASE_DIR}/xboot.bin" >&2
	return 0
}

build_bootloader_uboot_nand()
{
	cd ${SOURCE_DIR}/uboot || return 1

	make distclean
	make x210_nand_config
	make -j${CPU_NUM}
	mv u-boot.bin uboot_nand.bin
	if [ -f uboot_nand.bin ]; then
		cp uboot_nand.bin ${RELEASE_DIR}/uboot.bin
		cd ${RELEASE_DIR}
		${SOURCE_DIR}/tools/mkheader uboot.bin
		echo "^_^ uboot_nand.bin is finished successful!"
		exit
	else
		echo "make error,cann't compile u-boot.bin!"
		exit
	fi
}

build_bootloader_uboot_inand()
{
	cd ${SOURCE_DIR}/uboot || return 1

	make distclean
	make x210_sd_config
	make -j${CPU_NUM}
	mv u-boot.bin uboot_inand.bin
	if [ -f uboot_inand.bin ]; then 
		cp uboot_inand.bin ${RELEASE_DIR}/uboot.bin
		cd ${RELEASE_DIR}
		${SOURCE_DIR}/tools/mkheader uboot.bin
		echo "^_^ uboot_inand.bin is finished successful!"
		exit
	else
		echo "make error,cann't compile u-boot.bin!"
		exit
	fi
}


build_kernel()
{
	cd ${SOURCE_DIR}/kernel || return 1

	make ${INITRD_KERNEL_CONFIG} || return 1
	make -j${threads} || return 1
	dd if=${SOURCE_DIR}/kernel/arch/arm/boot/zImage of=${RELEASE_DIR}/zImage-initrd bs=2048 count=8192 conv=sync;

	make ${QT_KERNEL_CONFIG} || return 1
	make -j${threads} || return 1
	dd if=${SOURCE_DIR}/kernel/arch/arm/boot/zImage of=${RELEASE_DIR}/zImage-qt bs=2048 count=8192 conv=sync;

	echo "" >&2
	echo "^_^ initrd kernel path: ${RELEASE_DIR}/zImage-initrd" >&2
	echo "^_^ qt kernel path: ${RELEASE_DIR}/zImage-qt" >&2

	return 0
}

build_rootfs()
{
	cd ${SOURCE_DIR}/buildroot || return 1

	make ${BUILDROOT_CONFIG} || return 1
	make || return 1

	# copy rootfs.tar to release directory
	cp -v ${SOURCE_DIR}/buildroot/output/images/rootfs.tar ${RELEASE_DIR} || { return 1; }
}

# must root user
gen_qt_rootfs_ext3()
{
	if [ ! -f ${RELEASE_DIR}/rootfs.tar ]; then
		echo "not found rootfs.tar, please build rootfs" >&2
		return 1
	fi

	echo "making ext3 qt4.8 rootfs now,wait a moment..."
	cd ${RELEASE_DIR}
	rm -rf rootfs
	mkdir -p rootfs
	tar xf rootfs.tar -C rootfs
	
	rm rootfs_qt4.ext3
	rm -rf rootfs_img
	mkdir -p rootfs_img

	dd if=/dev/zero of=rootfs_qt4.ext3 bs=1024 count=122880
	mkfs.ext3 rootfs_qt4.ext3
	mount -o loop rootfs_qt4.ext3 ./rootfs_img

	cp ./rootfs/* ./rootfs_img -ar
	umount ./rootfs_img
	
	echo "^_^ make rootfs_qt4.ext3 successful!"
}

# must root user
gen_qt_rootfs_jffs2()
{
	if [ ! -f ${RELEASE_DIR}/rootfs.tar ]; then
		echo "not found rootfs.tar, please build rootfs" >&2
		return 1
	fi

	echo "making jffs2 qt4.8 rootfs now,wait a moment..."
	cd ${RELEASE_DIR}
	rm -rf rootfs
	mkdir -p rootfs
	tar xf rootfs.tar -C rootfs

	[ -e "rootfs" ] ||{ echo "error!can't find rootfs dir"; exit;}

	mkfs.jffs2 -r rootfs -o rootfs_qt4.jffs2 -e 0x20000 -s 0x800 --pad=0x5000000 -n
	echo "^_^ make rootfs_qt4.jffs2 successful!"
}

gen_qt_update_bin()
{
	# check image files
	if [ ! -f ${RELEASE_DIR}/xboot.bin ]; then
		echo "not found bootloader xboot.bin, please build bootloader" >&2
		return 1
	fi

	if [ ! -f ${RELEASE_DIR}/zImage-initrd ]; then
		echo "not found kernel zImage-initrd, please build kernel first" >&2
		return 1
	fi

	if [ ! -f ${RELEASE_DIR}/zImage-qt ]; then
		echo "not found kernel zImage-qt, please build kernel first" >&2
		return 1
	fi

	if [ ! -f ${RELEASE_DIR}/rootfs.tar ]; then
		echo "not found rootfs.tar, please build rootfs" >&2
		return 1
	fi

	rm -fr ${RELEASE_DIR}/tmp || return 1;
	rm -fr ${RELEASE_DIR}/qt-update.bin || return 1;
	mkdir -p ${RELEASE_DIR}/tmp || return 1;

	# copy image files
	cp ${RELEASE_DIR}/xboot.bin ${RELEASE_DIR}/tmp/;
	cp ${RELEASE_DIR}/zImage-initrd ${RELEASE_DIR}/tmp/;
	cp ${RELEASE_DIR}/zImage-qt ${RELEASE_DIR}/tmp/;
	cp ${RELEASE_DIR}/rootfs.tar ${RELEASE_DIR}/tmp/;

	# create md5sum.txt
	cd ${RELEASE_DIR}/tmp/;
	find . -type f -print | while read line; do
		if [ $line != 0 ]; then
			md5sum ${line} >> md5sum.txt
		fi
	done

	# mkisofs
	mkisofs -l -r -o ${RELEASE_DIR}/qt-update.bin ${RELEASE_DIR}/tmp/ || return 1;

	cd ${SOURCE_DIR} || return 1 
	rm -fr ${RELEASE_DIR}/tmp || return 1;
	return 0;
}

threads=4;
xboot=no;
uboot_inand=no;
uboot_nand=no;
kernel=no;
rootfs=no;
rootfs_ext3=no;
rootfs_jffs2=no;
update=no;

if [ -z $1 ]; then
	xboot=yes
	uboot_inand=no;
	uboot_nand=no;
	kernel=yes
	rootfs=yes
	rootfs_ext3=no;
	rootfs_jffs2=no;
	update=yes
fi

while [ "$1" ]; do
    case "$1" in
	-j=*)
		x=$1
		threads=${x#-j=}
		;;
	-x|--xboot)
		xboot=yes
	    ;;
	-ui|--uboot_inand)
		uboot_inand=yes
	    ;;
	-un|--uboot_nand)
		uboot_nand=yes
	    ;;
	-k|--kernel)
	    kernel=yes
	    ;;
	-r|--rootfs)
		rootfs=yes
	    ;;
	-re|--rootfs_ext3)
		rootfs_ext3=yes
	    ;;
	-rj|--rootfs_jffs2)
		rootfs_jffs2=yes
	    ;;
	-U|--update)
		update=yes
	    ;;
	-a|--all)
		xboot=yes
		kernel=yes
		rootfs=yes
		update=yes
	    ;;
	-h|--help)
	    cat >&2 <<EOF
Usage: mk [OPTION]
Build script for compile the source of telechips project.

  -j=n                 using n threads when building source project (example: -j=16)
  -x, --xboot          build bootloader xboot from source file
  -ui,--uboot_inand    build uboot for emmc
  -un,--uboot_nand     build uboot for nand flash
  -k, --kernel         build kernel from source file and using default config file
  -r, --rootfs         build root file system
  -re,--rootfs_ext3    build rootfs for emmc,used with uboot
  -rj,--rootfs_jffs2   build rootfs for nand,used with uboot
  -U, --update         gen update package update.bin,used with xboot
  -a, --all            build all, include anything
  -h, --help           display this help and exit
EOF
	    exit 0
	    ;;
	*)
	    echo "build.sh: Unrecognised option $1" >&2
	    exit 1
	    ;;
    esac
    shift
done

setup_environment || exit 1

if [ "${kernel}" = yes ]; then
	build_kernel || exit 1
fi

if [ "${xboot}" = yes ]; then
	build_bootloader_xboot || exit 1
fi

if [ "${uboot_inand}" = yes ]; then
	build_bootloader_uboot_inand || exit 1
fi

if [ "${uboot_nand}" = yes ]; then
	build_bootloader_uboot_nand || exit 1
fi

if [ "${rootfs}" = yes ]; then
	build_rootfs || exit 1
fi

if [ "${rootfs_ext3}" = yes ]; then
	gen_qt_rootfs_ext3 || exit 1
fi

if [ "${rootfs_jffs2}" = yes ]; then
	gen_qt_rootfs_jffs2 || exit 1
fi

if [ "${update}" = yes ]; then
	gen_qt_update_bin || exit 1
fi

exit 0

