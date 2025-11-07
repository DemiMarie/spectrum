# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>

.POSIX:

include ../../lib/common.mk
include file-list.mk

dest = build

DIRS = \
	dev \
	etc/s6-linux-init/env \
	etc/s6-linux-init/run-image/configs \
	etc/s6-linux-init/run-image/sd-notify-wrapper \
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
	ext \
	proc \
	run \
	sys

FIFOS = etc/s6-linux-init/run-image/service/s6-svscan-log/fifo

BUILD_FILES = build/etc/s6-rc

# This rule produces three files but Make only (portably)
# supports one output per rule.  Instead of resorting to temporary
# files, a timestamp file is created as the last step.  The actual
# outputs are produced as side-effects.
$(dest)/rootfs: ../../scripts/make-erofs.sh $(PACKAGES_FILE) $(FILES) $(BUILD_FILES) build/empty build/fifo file-list.mk
	set -euo pipefail; \
	mkdir -p $(dest); \
	{ \
	    cat $(PACKAGES_FILE) ;\
	    for file in $(FILES) $(LINKS); do printf '%s\n%s\n' $$file "$${file#image/}"; done ;\
	    for file in $(BUILD_FILES); do printf '%s\n%s\n' $$file $${file#build/}; done ;\
	    printf 'build/empty\n%s\n' $(DIRS) ;\
	    printf 'build/fifo\n%s\n' $(FIFOS) ;\
	} | ../../scripts/make-erofs.sh $(dest)/rootfs

build/timestamp: $(dest)/rootfs
	$(VERITYSETUP) format \
		--root-hash-file $(dest)/rootfs.verity.roothash \
		-- $(dest)/rootfs $(dest)/rootfs.verity.superblock
	# Add trailing newline
	echo >> $(dest)/rootfs.verity.roothash
	touch -- $(dest)/timestamp

build/fifo:
	mkdir -p build
	mkfifo -m 0600 $@

build/empty:
	mkdir -p $@

# s6-rc-compile's input is a directory, but that doesn't play nice
# with Make, because it won't know to update if some file in the
# directory is changed, or a file is created or removed in a
# subdirectory.  Using the whole source directory could also end up
# including files that aren't intended to be part of the input, like
# temporary editor files or .license files.  So for all these reasons,
# only explicitly listed files are made available to s6-rc-compile.
build/etc/s6-rc: $(S6_RC_FILES) file-list.mk
	mkdir -p $$(dirname $@)
	rm -rf $@
	set -uo pipefail && dir=$$(mktemp -d) && \
	    { tar -c $(S6_RC_FILES) | tar -C $$dir -x --strip-components 3; } && \
	    s6-rc-compile $@ $$dir; \
	    exit=$$?; rm -r $$dir; exit $$exit

clean:
	-chmod -Rf +w build
	rm -rf build
.PHONY: clean

build/live.img: ../../scripts/format-uuid.sh ../../scripts/make-gpt.sh ../../scripts/sfdisk-field.awk $(dest)/timestamp
	../../scripts/make-gpt.sh $@.tmp \
	    $(dest)/rootfs.verity.superblock:verity:$$(../../scripts/format-uuid.sh "$$(dd if=$(dest)/rootfs.verity.roothash bs=32 skip=1 count=1 status=none)") \
	    $(dest)/rootfs:root:$$(../../scripts/format-uuid.sh "$$(head -c 32 $(dest)/rootfs.verity.roothash)")
	mv $@.tmp $@

debug:
	$(GDB) -q \
	    -ex 'set substitute-path .. $(LINUX_SRC)' \
	    -ex 'target remote build/gdb.sock' \
	    $(VMLINUX)
.PHONY: debug

run: build/live.img
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
	    -append "earlycon console=hvc0 roothash=$$(< $(dest)/rootfs.verity.roothash) intel_iommu=on nokaslr" \
	    -device virtio-keyboard \
	    -device virtio-mouse \
	    -device virtio-gpu \
	    -netdev user,id=net0 \
	    -device e1000e,netdev=net0 \
	    -vga none \
	    -device vhost-vsock-pci,guest-cid=3
.PHONY: run
