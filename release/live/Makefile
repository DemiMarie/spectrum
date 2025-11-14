# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2025 Alyssa Ross <hi@alyssa.is>

.POSIX:

include ../../lib/common.mk

DTBS ?= build/empty

dest = build/live.img

$(dest): ../../scripts/format-uuid.bash ../../scripts/make-gpt.sh ../../scripts/sfdisk-field.awk build/boot.fat $(ROOT_FS_IMAGES)
	uuids=$$(awk -f ../../scripts/format-uuid.awk < $(ROOT_FS_VERITY_ROOTHASH)) && \
	set -euo pipefail -- $$uuids && \
	bash ../../scripts/make-gpt.sh $@.tmp \
	    build/boot.fat:c12a7328-f81f-11d2-ba4b-00a0c93ec93b \
	    $(ROOT_FS_VERITY):verity:$$3:$(VERSION):162MiB \
	    $(ROOT_FS):root:$$1:$(VERSION):20000MiB \
	    /dev/null:verity:$$4:$(VERSION):162MiB \
	    /dev/null:root:$$2:$(VERSION):20000MiB
	mv $@.tmp $@

build/empty:
	mkdir -p $@

build/boot.fat: $(SYSTEMD_BOOT_EFI) $(EFI_IMAGE) build/empty
	$(TRUNCATE) -s 440401920 $@
	$(MKFS_FAT) $@
	$(MMD) -i $@ ::/EFI ::/EFI/BOOT ::/EFI/Linux
	$(MCOPY) -i $@ $(EFI_IMAGE) ::/EFI/Linux/Spectrum_$(VERSION).efi
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
