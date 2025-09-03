# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>

.POSIX:

basedir = ../..
include $(basedir)/lib/erofs.mk

DIRS = \
	dev \
	etc/s6-linux-init/env \
	etc/s6-linux-init/run-image/configs \
	etc/s6-linux-init/run-image/service/dbus/instance \
	etc/s6-linux-init/run-image/service/dbus/instances \
	etc/s6-linux-init/run-image/service/dbus/template/data \
	etc/s6-linux-init/run-image/service/dbus/template/env \
	etc/s6-linux-init/run-image/service/serial-getty/instance \
	etc/s6-linux-init/run-image/service/serial-getty/instances \
	etc/s6-linux-init/run-image/service/vhost-user-fs/instance \
	etc/s6-linux-init/run-image/service/vhost-user-fs/instances \
	etc/s6-linux-init/run-image/service/vhost-user-fs/template/data \
	etc/s6-linux-init/run-image/service/vhost-user-fs/template/env \
	etc/s6-linux-init/run-image/service/vhost-user-gpu/instance \
	etc/s6-linux-init/run-image/service/vhost-user-gpu/instances \
	etc/s6-linux-init/run-image/service/vhost-user-gpu/template/env \
	etc/s6-linux-init/run-image/service/vmm/instance \
	etc/s6-linux-init/run-image/service/vmm/instances \
	etc/s6-linux-init/run-image/service/vmm/template/data \
	etc/s6-linux-init/run-image/service/vmm/template/env \
	etc/s6-linux-init/run-image/service/xdg-desktop-portal-spectrum-host/instance \
	etc/s6-linux-init/run-image/service/xdg-desktop-portal-spectrum-host/instances \
	etc/s6-linux-init/run-image/service/xdg-desktop-portal-spectrum-host/template/data \
	etc/s6-linux-init/run-image/service/xdg-desktop-portal-spectrum-host/template/env \
	etc/s6-linux-init/run-image/user \
	etc/s6-linux-init/run-image/vm/by-id \
	etc/s6-linux-init/run-image/vm/by-name \
	etc/s6-linux-init/run-image/wait \
	ext \
	run \
	proc \
	sys

FIFOS = etc/s6-linux-init/run-image/service/s6-svscan-log/fifo

all: $(dest)

# veritysetup format produces two files, but Make only (portably)
# supports one output per rule, so we combine the two outputs then
# define two more rules to separate them again.
build/rootfs.verity: $(dest)
	$(VERITYSETUP) format $(dest) build/rootfs.verity.superblock.tmp \
	    | awk -F ':[[:blank:]]*' '$$1 == "Root hash" {print $$2; exit}' \
	    > build/rootfs.verity.roothash.tmp
	cat build/rootfs.verity.roothash.tmp build/rootfs.verity.superblock.tmp \
	    > $@
	rm build/rootfs.verity.roothash.tmp build/rootfs.verity.superblock.tmp
build/rootfs.verity.roothash: build/rootfs.verity
	head -n 1 build/rootfs.verity > $@
build/rootfs.verity.superblock: build/rootfs.verity
	tail -n +2 build/rootfs.verity > $@

build/live.img: ../../scripts/format-uuid.sh ../../scripts/make-gpt.sh ../../scripts/sfdisk-field.awk build/rootfs.verity.superblock build/rootfs.verity.roothash $(dest)
	../../scripts/make-gpt.sh $@.tmp \
	    build/rootfs.verity.superblock:verity:$$(../../scripts/format-uuid.sh "$$(dd if=build/rootfs.verity.roothash bs=32 skip=1 count=1 status=none)") \
	    $(dest):root:$$(../../scripts/format-uuid.sh "$$(head -c 32 build/rootfs.verity.roothash)")
	mv $@.tmp $@

debug:
	$(GDB) -q \
	    -ex 'set substitute-path .. $(LINUX_SRC)' \
	    -ex 'target remote build/gdb.sock' \
	    $(VMLINUX)
.PHONY: debug

run: build/live.img $(EXT_FS) build/rootfs.verity.roothash
	@set -x && \
	ext="$$(mktemp build/spectrum-rootfs-extfs.XXXXXXXXXX.img)" && \
	truncate -s 10G "$$ext" && \
	mkfs.btrfs "$$ext" && \
	exec 3<>"$$ext" && \
	rm -f "$$ext" && \
	set +x && \
	exec ../../scripts/run-qemu.sh -cpu max -m 4G \
	    -machine virtualization=on \
	    -kernel $(KERNEL) \
	    -initrd $(INITRAMFS) \
	    -gdb unix:build/gdb.sock,server,nowait \
	    -qmp unix:build/vmm.sock,server,nowait \
	    -monitor vc \
	    -parallel none \
	    -chardev vc,id=virtiocon0 \
	    -device virtio-serial \
	    -device virtconsole,chardev=virtiocon0 \
	    -drive file=build/live.img,if=virtio,format=raw,readonly=on \
	    -drive file=/proc/self/fd/3,if=virtio,format=raw \
	    -append "earlycon console=hvc0 roothash=$$(< build/rootfs.verity.roothash) intel_iommu=on nokaslr" \
	    -device virtio-keyboard \
	    -device virtio-mouse \
	    -device virtio-gpu \
	    -netdev user,id=net0 \
	    -device e1000e,netdev=net0 \
	    -vga none \
	    -device vhost-vsock-pci,guest-cid=3
.PHONY: run
