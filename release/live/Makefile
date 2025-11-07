# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2025 Alyssa Ross <hi@alyssa.is>

.POSIX:

include ../../lib/common.mk

DTBS ?= build/empty

dest = build/live.img

$(dest): ../../scripts/format-uuid.sh ../../scripts/make-gpt.sh ../../scripts/sfdisk-field.awk build/boot.fat $(ROOT_FS_IMAGES)
	../../scripts/make-gpt.sh $@.tmp \
	    build/boot.fat:c12a7328-f81f-11d2-ba4b-00a0c93ec93b \
	    $(ROOT_FS_VERITY):verity:$$(../../scripts/format-uuid.sh "$$(dd if=$(ROOT_FS_VERITY_ROOTHASH) bs=32 skip=1 count=1 status=none)") \
	    $(ROOT_FS):root:$$(../../scripts/format-uuid.sh "$$(head -c 32 $(ROOT_FS_VERITY_ROOTHASH))")
	mv $@.tmp $@

build/empty:
	mkdir -p $@

build/spectrum.efi: $(DTBS) $(KERNEL) $(INITRAMFS) $(ROOT_FS_VERITY_ROOTHASH)
	{ \
	    printf "[UKI]\nDeviceTreeAuto=" && \
	    find $(DTBS) -name '*.dtb' -print0 | tr '\0' ' ' ;\
	} | $(UKIFY) build \
	    --output $@ \
	    --config /dev/stdin \
	    --linux $(KERNEL) \
	    --initrd $(INITRAMFS) \
	    --os-release $$'NAME="Spectrum"\n' \
	    --cmdline "ro intel_iommu=on roothash=$$(cat $(ROOT_FS_VERITY_ROOTHASH))"

build/boot.fat: $(SYSTEMD_BOOT_EFI) build/spectrum.efi
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
