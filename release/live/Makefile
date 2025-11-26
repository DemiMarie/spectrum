# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2025 Alyssa Ross <hi@alyssa.is>

.POSIX:

include ../../lib/common.mk

dest = build/live.img

$(dest): ../../scripts/format-uuid.awk ../../scripts/make-gpt.sh ../../scripts/sfdisk-field.awk build/boot.fat $(ROOT_FS_IMAGES)
	../../scripts/make-gpt.sh $@.tmp \
	    build/boot.fat:c12a7328-f81f-11d2-ba4b-00a0c93ec93b \
	    $(ROOT_FS_VERITY):verity:$$(awk -f ../../scripts/format-uuid.awk "$$(dd if=$(ROOT_FS_VERITY_ROOTHASH) bs=32 skip=1 count=1 status=none)"):Spectrum_'$(VERSION).verity:162' \
	    $(ROOT_FS_IMAGE):root:$$(awk -f ../../scripts/format-uuid.awk "$$(head -c 32 $(ROOT_FS_VERITY_ROOTHASH))"):Spectrum_'$(VERSION):20000' \
	    /dev/null:verity:18f2ccff-92f1-4bb1-a80e-24f76ecda90c:_empty:162 \
	    /dev/null:root:ec0c5ff3-f6b1-4adf-82b4-61336c4d135f:_empty:20000
	mv $@.tmp $@

build/boot.fat: $(SYSTEMD_BOOT_EFI) $(SPECTRUM_EFI)
	mkdir -p build
	$(TRUNCATE) -s 440401920 $@
	$(MKFS_FAT) $@
	$(MMD) -i $@ ::/EFI ::/EFI/BOOT ::/EFI/Linux
	$(MCOPY) -i $@ $(SPECTRUM_EFI) ::/EFI/Linux/'Spectrum_$(VERSION).efi'
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
