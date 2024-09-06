# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>

.POSIX:

include ../../lib/common.mk

dest = build/rootfs.erofs

FILES = \
	etc/fonts/fonts.conf \
	etc/fstab \
	etc/group \
	etc/init \
	etc/login \
	etc/mdev.conf \
	etc/mdev/listen \
	etc/mdev/net/add \
	etc/mdev/wait \
	etc/parse-devname \
	etc/passwd \
	etc/s6-linux-init/env/WAYLAND_DISPLAY \
	etc/s6-linux-init/env/XDG_RUNTIME_DIR \
	etc/s6-linux-init/run-image/service/dbus/notification-fd \
	etc/s6-linux-init/run-image/service/dbus/run \
	etc/s6-linux-init/run-image/service/dbus/template/notification-fd \
	etc/s6-linux-init/run-image/service/dbus/template/run \
	etc/s6-linux-init/run-image/service/getty-tty1/run \
	etc/s6-linux-init/run-image/service/getty-tty2/run \
	etc/s6-linux-init/run-image/service/getty-tty3/run \
	etc/s6-linux-init/run-image/service/getty-tty4/run \
	etc/s6-linux-init/run-image/service/s6-svscan-log/notification-fd \
	etc/s6-linux-init/run-image/service/s6-svscan-log/run \
	etc/s6-linux-init/run-image/service/serial-getty/notification-fd \
	etc/s6-linux-init/run-image/service/serial-getty/run \
	etc/s6-linux-init/run-image/service/serial-getty/template/run \
	etc/s6-linux-init/run-image/service/vhost-user-fs/notification-fd \
	etc/s6-linux-init/run-image/service/vhost-user-fs/run \
	etc/s6-linux-init/run-image/service/vhost-user-fs/template/notification-fd \
	etc/s6-linux-init/run-image/service/vhost-user-fs/template/run \
	etc/s6-linux-init/run-image/service/vhost-user-gpu/notification-fd \
	etc/s6-linux-init/run-image/service/vhost-user-gpu/run \
	etc/s6-linux-init/run-image/service/vhost-user-gpu/template/data/check \
	etc/s6-linux-init/run-image/service/vhost-user-gpu/template/notification-fd \
	etc/s6-linux-init/run-image/service/vhost-user-gpu/template/run \
	etc/s6-linux-init/run-image/service/vmm/notification-fd \
	etc/s6-linux-init/run-image/service/vmm/run \
	etc/s6-linux-init/run-image/service/vmm/template/notification-fd \
	etc/s6-linux-init/run-image/service/xdg-desktop-portal-spectrum-host/notification-fd \
	etc/s6-linux-init/run-image/service/xdg-desktop-portal-spectrum-host/run \
	etc/s6-linux-init/run-image/service/xdg-desktop-portal-spectrum-host/template/notification-fd \
	etc/s6-linux-init/run-image/service/xdg-desktop-portal-spectrum-host/template/run \
	etc/s6-linux-init/scripts/rc.init \
	etc/xdg/weston/autolaunch \
	etc/xdg/weston/weston.ini \
	usr/share/dbus-1/services/org.freedesktop.portal.Documents.service \
	usr/bin/create-vm-dependencies \
	usr/bin/lsvm \
	usr/bin/run-appimage \
	usr/bin/vm-console \
	usr/bin/vm-import \
	usr/bin/vm-start \
	usr/bin/vm-stop \
	usr/bin/xdg-open

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
	etc/s6-linux-init/run-image/vm \
	ext \
	run \
	proc \
	sys

FIFOS = etc/s6-linux-init/run-image/service/s6-svscan-log/fifo

# These are separate because they need to be included, but putting
# them as make dependencies would confuse make.
LINKS = \
	bin \
	etc/s6-linux-init/run-image/opengl-driver \
	etc/s6-linux-init/run-image/service/vmm/template/run \
	lib \
	sbin

BUILD_FILES = build/etc/s6-rc

$(dest): ../../scripts/make-erofs.sh $(FILES) $(BUILD_FILES) build/empty build/fifo
	( \
	    cat $$PACKAGES ;\
	    for file in $(FILES) $(LINKS); do printf '%s\n%s\n' $$file $$file; done ;\
	    for file in $(BUILD_FILES); do printf '%s\n%s\n' $$file $${file#build/}; done ;\
	    printf 'build/empty\n%s\n' $(DIRS) ;\
	    printf 'build/fifo\n%s\n' $(FIFOS) ;\
	) | ../../scripts/make-erofs.sh $@

build/fifo:
	mkdir -p build
	mkfifo -m 0600 $@

build/empty:
	mkdir -p $@

S6_RC_FILES = \
	etc/s6-rc/card0/type \
	etc/s6-rc/card0/up \
	etc/s6-rc/core/type \
	etc/s6-rc/core/up \
	etc/s6-rc/kvm/timeout-up \
	etc/s6-rc/kvm/type \
	etc/s6-rc/kvm/up \
	etc/s6-rc/mdevd-coldplug/dependencies \
	etc/s6-rc/mdevd-coldplug/type \
	etc/s6-rc/mdevd-coldplug/up \
	etc/s6-rc/mdevd/notification-fd \
	etc/s6-rc/mdevd/run \
	etc/s6-rc/mdevd/type \
	etc/s6-rc/ok-all/contents \
	etc/s6-rc/ok-all/type \
	etc/s6-rc/static-nodes/type \
	etc/s6-rc/static-nodes/up \
	etc/s6-rc/sys-vmms/dependencies \
	etc/s6-rc/sys-vmms/type \
	etc/s6-rc/sys-vmms/up \
	etc/s6-rc/vm-env/contents \
	etc/s6-rc/vm-env/type \
	etc/s6-rc/vmm-env/contents \
	etc/s6-rc/vmm-env/type \
	etc/s6-rc/weston/dependencies \
	etc/s6-rc/weston/notification-fd \
	etc/s6-rc/weston/type \
	etc/s6-rc/weston/run

# s6-rc-compile's input is a directory, but that doesn't play nice
# with Make, because it won't know to update if some file in the
# directory is changed, or a file is created or removed in a
# subdirectory.  Using the whole source directory could also end up
# including files that aren't intended to be part of the input, like
# temporary editor files or .license files.  So for all these reasons,
# only explicitly listed files are made available to s6-rc-compile.
build/etc/s6-rc: $(S6_RC_FILES)
	mkdir -p $$(dirname $@)
	rm -rf $@

	dir=$$(mktemp -d) && \
	    tar -c $(S6_RC_FILES) | tar -C $$dir -x --strip-components 2 && \
	    s6-rc-compile $@ $$dir; \
	    exit=$$?; rm -r $$dir; exit $$exit

clean:
	-chmod -Rf +w build
	rm -rf build
.PHONY: clean

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
	mkfs.ext4 "$$ext" && \
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
	    -serial none \
	    -chardev vc,id=virtiocon0 \
	    -device virtio-serial \
	    -device virtconsole,chardev=virtiocon0 \
	    -drive file=build/live.img,if=virtio,format=raw,readonly=on \
	    -drive file=/proc/self/fd/3,if=virtio,format=raw \
	    -append "console=hvc0 roothash=$$(< build/rootfs.verity.roothash) intel_iommu=on nokaslr" \
	    -device virtio-keyboard \
	    -device virtio-mouse \
	    -device virtio-gpu \
	    -netdev user,id=net0 \
	    -device e1000e,netdev=net0 \
	    -vga none \
	    -device vhost-vsock-pci,guest-cid=3
.PHONY: run
