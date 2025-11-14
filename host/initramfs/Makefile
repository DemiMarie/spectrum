# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>

.POSIX:

include ../../lib/common.mk

dest = build/initramfs

RUN_IMAGE = build/live.img

$(dest): $(MICROCODE) build/local.cpio $(PACKAGES_CPIO)
	cat /dev/null $(MICROCODE) > $@
	cat build/local.cpio $(PACKAGES_CPIO) | gzip -9n >> $@

# etc/init isn't included in ETC_FILES, because it gets installed to
# the root.
ETC_FILES = etc/getuuids etc/probe etc/fstab etc/mdev.conf
MOUNTPOINTS = dev mnt/root proc sys tmp

build/local.cpio: $(ETC_FILES) etc/init build/mountpoints
	printf "%s\n" $(ETC_FILES) | \
	    awk '{while (length) { print; sub("/?[^/]*$$", "") }}' | \
	    sort -u | \
	    $(CPIO) -o $(CPIOFLAGS) > $@
	cd etc && echo init | $(CPIO) -o $(CPIOFLAGS) -AF ../$@
	cd build/mountpoints && printf "%s\n" $(MOUNTPOINTS) | \
	    awk '{while (length) { print; sub("/?[^/]*$$", "") }}' | \
	    sort -u | \
	    $(CPIO) -o $(CPIOFLAGS) -AF ../../$@

build/mountpoints:
	rm -rf build/mountpoints
	mkdir -p build/mountpoints
	cd build/mountpoints && mkdir -p $(MOUNTPOINTS)
	find build/mountpoints -mindepth 1 -exec touch -d @0 {} ';'

build/live.img: ../../scripts/format-uuid.awk ../../scripts/make-gpt.sh ../../scripts/sfdisk-field.awk build/boot.fat $(ROOT_FS_IMAGES)
	uuids=$$(awk -f ../../scripts/format-uuid.awk < $(ROOT_FS_VERITY_ROOTHASH)) && \
	set -euo pipefail -- $$uuids && \
	bash ../../scripts/make-gpt.sh $@.tmp \
	    $(ROOT_FS_VERITY):verity:$$3 \
	    $(ROOT_FS):root:$$1
	mv $@.tmp $@

build/loop.tar: build/live.img
	$(TAR) -cf $@ build/live.img

build/loop.img: ../../scripts/make-gpt.sh ../../scripts/sfdisk-field.awk build/loop.ext4
	bash ../../scripts/make-gpt.sh $@.tmp \
	    build/loop.ext4:56a3bbc3-aefa-43d9-a64d-7b3fd59bbc4e
	mv $@.tmp $@

clean:
	rm -rf build
.PHONY: clean

run: $(dest) $(RUN_IMAGE) $(ROOT_FS_VERITY_ROOTHASH)
	@../../scripts/run-qemu.sh -m 4G \
	    -machine virtualization=on \
	    -kernel $(KERNEL) \
	    -initrd $(dest) \
	    -append "ro earlycon console=hvc0 intel_iommu=on roothash=$$(< "$$ROOT_FS_VERITY_ROOTHASH") nokaslr" \
	    -cpu max \
	    -gdb unix:build/gdb.sock,server,nowait \
	    -parallel none \
	    -chardev vc,id=virtiocon0 \
	    -device virtio-serial \
	    -device virtconsole,chardev=virtiocon0 \
	    -device virtio-keyboard \
	    -device virtio-mouse \
	    -device virtio-gpu \
	    -vga none \
	    -device qemu-xhci \
	    -device usb-storage,drive=drive1,removable=true \
	    -drive file=$(RUN_IMAGE),id=drive1,format=raw,if=none,readonly=true
.PHONY: run
