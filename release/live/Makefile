# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2025 Alyssa Ross <hi@alyssa.is>

.POSIX:

include ../../lib/common.mk
include ../../lib/kcmdline-utils.mk

DTBS ?= build/empty

dest = build/live.img

$(dest): build/boot.fat $(LIVE_IMAGE_DEPS) $(ROOT_FS) $(ROOT_FS_VERITY) $(ROOT_FS_VERITY_ROOTHASH)
	../../scripts/make-live-image.sh release $@

build/empty:
	mkdir -p $@

build/boot.fat: $(SYSTEMD_BOOT_EFI) $(EFI_IMAGE) build/empty
	ln -sf -- "$$EFI_IMAGE" build/spectrum.efi
	$(TRUNCATE) -s 440401920 $@
	$(MKFS_FAT) $@
	$(MMD) -i $@ ::/EFI ::/EFI/BOOT ::/EFI/Linux
	$(MCOPY) -i $@ build/spectrum.efi ::/EFI/Linux
	$(MCOPY) -i $@ $(SYSTEMD_BOOT_EFI) ::/EFI/BOOT/$(EFINAME)

clean:
	rm -rf build
.PHONY: clean

run: $(dest)
	@../../scripts/run-qemu.sh -m 4G \
	    -machine virtualization=on \
	    -cpu max \
	    -device virtio-keyboard \
	    -device virtio-mouse \
	    -device virtio-gpu \
	    -parallel none \
	    -vga none \
	    -device qemu-xhci \
	    -device usb-storage,drive=drive1,removable=true \
	    -drive file=$(OVMF_CODE),format=raw,if=pflash,readonly=true \
	    -drive file=$(dest),id=drive1,format=raw,if=none,readonly=true
.PHONY: run
