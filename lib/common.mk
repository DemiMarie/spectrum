# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021, 2023, 2025 Alyssa Ross <hi@alyssa.is>

BACKGROUND = background
CPIO = cpio
CPIOFLAGS = --reproducible -R +0:+0 -H newc
CROSVM = crosvm
CROSVM_DEVICE_GPU = $(CROSVM) device gpu
CROSVM_RUN = $(CROSVM) run
GDB = gdb
MCOPY = mcopy
MKFS_FAT = mkfs.fat
MMD = mmd
ROOT_FS_IMAGE = $(ROOT_FS)/rootfs
ROOT_FS_IMAGES = $(ROOT_FS_IMAGE) $(ROOT_FS_VERITY_ROOTHASH) $(ROOT_FS_VERITY)
ROOT_FS_VERITY = $(ROOT_FS)/rootfs.verity.superblock
ROOT_FS_VERITY_ROOTHASH = $(ROOT_FS)/rootfs.verity.roothash
S6_IPCSERVER_SOCKETBINDER = s6-ipcserver-socketbinder
TAR = tar
TRUNCATE = truncate
UKIFY = ukify
VERITYSETUP = veritysetup
VIRTIOFSD = virtiofsd

PACKAGES_FILE != \
	if [ -n "$$PACKAGES" ]; then \
	    if ! [ -e build/packages.txt ] || ! cmp -s "$$PACKAGES" build/packages.txt; then \
	        mkdir -p build && cp -f "$$PACKAGES" build/packages.txt ;\
	    fi ;\
	    echo build/packages.txt ;\
	fi
