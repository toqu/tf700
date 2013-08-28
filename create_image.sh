#!/bin/bash

set -u # Abort, when undefined variables are used

export ROOT_DIR=$(pwd)
export CROSS_COMPILE=${ROOT_DIR}/tools/toolchain/bin/arm-linux-gnueabihf- 
export ARCH=arm

LINARO_TOOLCHAIN_ARCHIVE_DL_LOC=https://launchpad.net/linaro-toolchain-binaries/trunk/2013.04/+download/gcc-linaro-arm-linux-gnueabihf-4.7-2013.04-20130415_linux.tar.bz2
LINARO_TOOLCHAIN_ARCHIVE=${ROOT_DIR}/gcc-linaro-arm-linux-gnueabihf-4.7-2013.04-20130415_linux.tar.bz2
LINARO_TOOLCHAIN_ARCHIVE_MD5=${ROOT_DIR}/gcc-linaro-arm-linux-gnueabihf-4.7-2013.04-20130415_linux.tar.bz2.md5

#export KERNEL_VARIANT=linux-3.11-rc6 KERNEL_DEFCONFIG=tegra_defconfig
#export KERNEL_VARIANT=linux-3.1.10_hb KERNEL_DEFCONFIG=tegra3_hb_defconfig
#export KERNEL_VARIANT=linux_3.1.10_cm KERNEL_DEFCONFIG=tegra3_hb_defconfig
#export KERNEL_VARIANT=linux_3.1_hb_oc KERNEL_DEFCONFIG=tf700t_defconfig
export KERNEL_VARIANT=linux-3.1.10_hb_mored KERNEL_DEFCONFIG=tf700t_defconfig

export KERNEL_BASE_DIR=${ROOT_DIR}/source/kernel
export KERNEL_SRC_DIR=${ROOT_DIR}/source/kernel

export KERNEL_SRC=${KERNEL_BASE_DIR}/${KERNEL_VARIANT}
export KERNEL_OUT=${KERNEL_BASE_DIR}/${KERNEL_VARIANT}_out
export MODULES_OUT=${KERNEL_BASE_DIR}/${KERNEL_VARIANT}_out_modules


REBUILD=0
MENUCONFIG=0
OLDCONFIG=0


NEEDED_PROGRAMS="md5sum git tar abootimg make sed find dd date ln bunzip2 xz wget"

# Check, if dependencies are met
for program in ${NEEDED_PROGRAMS}
do
    if [ -z "$(which ${program})" ]
    then
	echo "Program \"$program\" not installed! Aborting..."
	exit 1
    fi
done

# check, if toolchain is in place
if [ -e ${CROSS_COMPILE}gcc  ]
then
    echo "$0: GCC toolchain found"
else
    echo "$0: Acquire toolchain..."
    cd ${ROOT_DIR}
    
    LINARO_TOOLCHAIN_ARCHIVE_MD5_BN=$(basename ${LINARO_TOOLCHAIN_ARCHIVE_MD5})
    
    md5sum -c $(basename ${LINARO_TOOLCHAIN_ARCHIVE_MD5})
    if [ "0" -ne  "$?" ]
    then
	echo "$0: No valid toolchain archive found... downloading"
	
	rm -f ${LINARO_TOOLCHAIN_ARCHIVE} &> /dev/null
	wget ${LINARO_TOOLCHAIN_ARCHIVE_DL_LOC}
	
	if [ "0" -ne "$?" ]
	then
	    echo "$0: Failed to download archive"
	    exit 1
	fi
	echo "$0: Check image..."
	md5sum -c $(basename ${LINARO_TOOLCHAIN_ARCHIVE_MD5})
	if [ "0" -ne  "$?" ]
	then
	    echo "$0: Downloaded archive invalid!"
	    exit 1
	fi

    fi
    
    echo "$0: Extract archive..."
    tar xjvf ${LINARO_TOOLCHAIN_ARCHIVE} --strip-components=1 -C tools/toolchain
    
    # Paranoia check 
    if [ ! -e ${CROSS_COMPILE}gcc  ]
    then
	echo "$0: Toolchain not OK"
    fi
    
fi


# Prepare blobutils
if [ -e tools/blobtools/blobpack ]
then
    echo "$0: blobpack found"
else
    git submodule update --init tools/blobtools
    if [ "0" -ne "$?" ]
    then
	echo "$0: Failed to checkout blobtools"
	exit 1
    fi
    
    cd tools/blobtools && make && cd ../..

    if [ ! -e tools/blobtools/blobpack ]
    then
	echo "$0: Build of blobtools failed!"
	exit 1
    fi
fi

# Prepare busybox
if [ -e source/busybox/out/busybox ]
then
    echo "$0: busybox found"
else
    git submodule update --init source/busybox/src
    
    if [ "0" -ne "$?" ]
    then
	echo "$0: Failed to checkout busybox"
	exit 1
    fi

    cd source/busybox/src
    export KBUILD_OUTPUT=../out
    make
    make install
    cd ../../..

    if [ ! -e source/busybox/out/busybox ]
    then
	echo "$0: Build of busybox failed!"
	exit 1
    fi
    
fi

echo "$0: Accquire Kernel sources"
git submodule update --init ${KERNEL_SRC}
if [ "0" -ne "$?" ]
then
    echo "Failed!"
    exit 1
fi

if [ "1" -eq "$#" ]
then
    if [ "$1" == "REBUILD" ]
    then
	echo "$0: REBUILD!"
	REBUILD=1
    elif [ "$1" == "menuconfig" ]
    then
	echo "$0: MENUCONFIG!"
	MENUCONFIG=1
    elif [ "$1" == "oldconfig" ]
    then
	echo "OLDCONFIG!"
	OLDCONFIG=1
    else
	echo "$0: Wrong command!"
	exit 1
    fi
fi

# Build kernel
cd ${KERNEL_SRC}
if [ ! -d ${KERNEL_OUT} ]
then
    mkdir ${KERNEL_OUT}
fi

if [ "1" -eq "${REBUILD}" ]
then
    echo "$0: Call defconfig"
    make -j4 O=${KERNEL_OUT} ${KERNEL_DEFCONFIG}
    if [ "0" -ne "$?" ]
    then
	echo "$0: make ${KERNEL_DEFCONFIG} failed"
	exit 1
    fi
fi

if [ "1" -eq "${OLDCONFIG}" ]
then
    echo "$0: Call oldconfig"
    make -j4 O=${KERNEL_OUT} oldconfig
    if [ "0" -ne "$?" ]
    then
	echo "$0: make oldconfig failed"
	exit 1
    fi
    
    echo "$0: Success"
    exit 0
fi

if [ "1" -eq "${MENUCONFIG}" ]
then
    echo "$0: Call menuconfig"
    make -j4 O=${KERNEL_OUT} menuconfig
    if [ "0" -ne "$?" ]
    then
	echo "$0: make menuconfig failed"
	exit 1
    fi
    
    echo "$0: Success"
    exit 0
fi

# Clean sourcecode (this does not affect the data in KERNEL_OUT)
echo "$0: make mrproper on sources"
make mrproper

# Build zImage
echo "$0: make zImage"
make -j4 O=${KERNEL_OUT} zImage
if [ "0" -ne "$?" ]
then
    echo "$0: make zImage failed"
    beep -l 30 -r 10
    exit 1
fi
echo "$0: make modules"
make -j4 modules O=${KERNEL_OUT} DESTDIR=${MODULES_OUT}
if [ "0" -ne "$?" ]
then
    echo "$0: make modules failed"
    beep -l 30 -r 10
    exit 1
fi
echo "$0: make modules_install"
make -j4 modules_install O=${KERNEL_OUT} INSTALL_MOD_PATH=${MODULES_OUT}
if [ "0" -ne "$?" ]
then
    echo "$0: make modules_install failed"
    beep -l 30 -r 10
    exit 1
fi

cd ${ROOT_DIR}

# Prepare RAMDISK
echo "$0: Prepare ramdisk"
rm -rf boot/${KERNEL_VARIANT}_img/
mkdir boot/${KERNEL_VARIANT}_img 

cp -af boot/ramdisk/stock   boot/${KERNEL_VARIANT}_img/ramdisk
cp -af boot/ramdisk/multi/* boot/${KERNEL_VARIANT}_img/ramdisk/
cp -a ${MODULES_OUT}/lib/modules boot/${KERNEL_VARIANT}_img/ramdisk/lib/

# Make RAMDISK
cd boot/${KERNEL_VARIANT}_img/ramdisk && find | cpio -H newc -o | lzma -9 > ../initrd.img && cd ../../..

abootimg --create boot/${KERNEL_VARIANT}_img/boot.img -k ${KERNEL_OUT}/arch/arm/boot/zImage -f boot/bootimg.cfg -r boot/${KERNEL_VARIANT}_img/initrd.img
if [ "0" -ne "$?" ]
then
    echo "$0: abootimg create failed"
    beep -l 30 -r 10
    exit 1
fi

# Build boot image
echo "$0: Build bootimage"
./tools/blobtools/blobpack boot/${KERNEL_VARIANT}_img/boot.blob.tosign LNX boot/${KERNEL_VARIANT}_img/boot.img
if [ "0" -ne "$?" ]
then
    echo "$0: blobpack failed"
    beep -l 30 -r 10
    exit 1
fi

echo -ne "-SIGNED-BY-SIGNBLOB-\0\0\0\0\0\0\0\0" | cat - boot/${KERNEL_VARIANT}_img/boot.blob.tosign > boot/${KERNEL_VARIANT}_img/boot.blob


echo "Successfully built bootimage"
echo "Flash via fastboot with the following command:"
echo -e "\tfastboot flash boot boot/${KERNEL_VARIANT}_img/boot.blob && fastboot reboot"

INSTALLER_NAME=installer_tf700t_$(date +%Y%m%d_%H%M).zip
./tools/prepare_installer.sh ${INSTALLER_NAME} ${KERNEL_OUT}/arch/arm/boot/zImage
if [ "0" -ne "$?" ]
then
    echo "Creation of installer failed!"
    beep -l 30 -r 10
    exit 1
fi

echo "Successfully created installer: ${INSTALLER_NAME}"
exit 0
