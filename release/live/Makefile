# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2025 Alyssa Ross <hi@alyssa.is>

.POSIX:

include ../../lib/common.mk
include ../../lib/kcmdline-utils.mk
include ../../lib/verity.mk

DTBS ?= build/empty

dest = build/live.img

$(dest): $(LIVE_IMAGE_DEPS) build/boot.fat
	../../scripts/make-live-image.sh release $(dest) $(ROOT_FS)

build/empty:
	mkdir -p $@

build/spectrum.efi: build/rootfs.verity.roothash $(DTBS) $(KERNEL) $(INITRAMFS) ../../lib/kcmdline-utils.mk
	set -euo pipefail; \
	$(READ_ROOTHASH) && \
	{ \
	    printf "[UKI]\nDeviceTreeAuto=" && \
	    find $(DTBS) -name '*.dtb' -print0 | tr '\0' ' ' ;\
	} | $(UKIFY) build \
	    --output $@ \
	    --config /dev/stdin \
	    --linux $(KERNEL) \
	    --initrd $(INITRAMFS) \
	    --os-release $$'NAME="Spectrum"\n' \
	    --cmdline "ro intel_iommu=on x-spectrum-roothash=$$roothash x-spectrum-version=$$VERSION"

install: build/rootfs.verity.superblock $(ROOT_FS) build/spectrum.efi $(dest)
	set -euo pipefail; \
	$(READ_ROOTHASH); \
	mkdir -p -- $(DESTDIR) build; \
	cp -- build/rootfs.verity.superblock $(DESTDIR)/"Spectrum_$$VERSION.verity"; \
	cp -- $(ROOT_FS) $(DESTDIR)/"Spectrum_$$VERSION.root"; \
	cp -- build/spectrum.efi $(DESTDIR)/"Spectrum_$$VERSION.efi"; \
	cp $(dest) $(DESTDIR)/live.img; \
	cd $(DESTDIR); \
	sha256sum live.img \
	   "Spectrum_$$VERSION.root" \
	   "Spectrum_$$VERSION.verity" \
	   "Spectrum_$$VERSION.efi" > SHA256SUMS

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
