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

# veritysetup format produces two files, but Make only (portably)
# supports one output per rule, so we combine the two outputs then
# define two more rules to separate them again.
build/rootfs.verity: $(ROOT_FS)
	mkdir -p build
	$(VERITYSETUP) format $(ROOT_FS) build/rootfs.verity.superblock.tmp \
	    | awk -F ':[[:blank:]]*' '$$1 == "Root hash" {print $$2; exit}' \
	    > build/rootfs.verity.roothash.tmp
	cat build/rootfs.verity.roothash.tmp build/rootfs.verity.superblock.tmp \
	    > $@
	rm build/rootfs.verity.roothash.tmp build/rootfs.verity.superblock.tmp
build/rootfs.verity.roothash: build/rootfs.verity
	head -n 1 build/rootfs.verity > $@
build/rootfs.verity.superblock: build/rootfs.verity
	tail -n +2 build/rootfs.verity > $@

build/live.img: ../../scripts/format-uuid.sh ../../scripts/make-gpt.sh ../../scripts/sfdisk-field.awk build/rootfs.verity.superblock build/rootfs.verity.roothash $(ROOT_FS)
	../../scripts/make-gpt.sh $@.tmp \
	    build/rootfs.verity.superblock:verity:$$(../../scripts/format-uuid.sh "$$(dd if=build/rootfs.verity.roothash bs=32 skip=1 count=1 status=none)") \
	    $(ROOT_FS):root:$$(../../scripts/format-uuid.sh "$$(head -c 32 build/rootfs.verity.roothash)")
	mv $@.tmp $@

build/loop.tar: build/live.img
	$(TAR) -cf $@ build/live.img

build/loop.img: ../../scripts/make-gpt.sh ../../scripts/sfdisk-field.awk build/loop.ext4
	../../scripts/make-gpt.sh $@.tmp \
	    build/loop.ext4:56a3bbc3-aefa-43d9-a64d-7b3fd59bbc4e
	mv $@.tmp $@

clean:
	rm -rf build
.PHONY: clean

run: $(dest) build/rootfs.verity.roothash $(RUN_IMAGE)
	@../../scripts/run-qemu.sh -m 4G \
	    -machine virtualization=on \
	    -kernel $(KERNEL) \
	    -initrd $(dest) \
	    -append "ro console=hvc0 intel_iommu=on roothash=$$(< build/rootfs.verity.roothash) nokaslr" \
	    -cpu max \
	    -gdb unix:build/gdb.sock,server,nowait \
	    -parallel none \
	    -serial none \
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
