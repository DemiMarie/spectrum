# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>

.POSIX:

include ../../lib/common.mk

dest = build/rootfs.erofs

FILES = \
	etc/fonts/fonts.conf \
	etc/fstab \
	etc/init \
	etc/login \
	etc/machine-id \
	etc/mdev/net/add \
	etc/os-release \
	etc/pam.d/login \
	etc/parse-devname \
	etc/security/namespace.conf \
	etc/sysctl.d/spectrum.conf \
	etc/systemd/system.conf.d/zspectrum.conf \
	etc/systemd/system/-.slice \
	etc/systemd/system/s6-init-start.service \
	etc/systemd/system/serial-getty@.service.d/90_force.conf \
	etc/systemd/system/systemd-tmpfiles-setup.service.d/90_spectrum.conf \
	etc/systemd/system/user@.service.d/99_spectrum-uid.conf \
	etc/tmpfiles.d/99-spectrum.conf \
	etc/udev/rules.d/99-spectrum-kvm.rules \
	etc/xdg/weston/autolaunch \
	etc/xdg/weston/weston.ini \
	usr/bin/assign-devices \
	usr/bin/create-vm-dependencies \
	usr/bin/run-appimage \
	usr/bin/run-vmm \
	usr/bin/vm-console \
	usr/bin/vm-import \
	usr/bin/vm-start \
	usr/bin/vm-stop \
	usr/bin/xdg-open \
	usr/lib/spectrum/s6-start \
	usr/share/dbus-1/services/org.freedesktop.portal.Documents.service \
	usr/share/spectrum/service/dbus/notification-fd \
	usr/share/spectrum/service/dbus/run \
	usr/share/spectrum/service/dbus/template/log/run \
	usr/share/spectrum/service/dbus/template/notification-fd \
	usr/share/spectrum/service/dbus/template/run \
	usr/share/spectrum/service/s6-svscan-log/notification-fd \
	usr/share/spectrum/service/s6-svscan-log/run \
	usr/share/spectrum/service/vhost-user-fs/notification-fd \
	usr/share/spectrum/service/vhost-user-fs/run \
	usr/share/spectrum/service/vhost-user-fs/template/log/run \
	usr/share/spectrum/service/vhost-user-fs/template/notification-fd \
	usr/share/spectrum/service/vhost-user-fs/template/run \
	usr/share/spectrum/service/vhost-user-gpu/notification-fd \
	usr/share/spectrum/service/vhost-user-gpu/run \
	usr/share/spectrum/service/vhost-user-gpu/template/data/check \
	usr/share/spectrum/service/vhost-user-gpu/template/log/run \
	usr/share/spectrum/service/vhost-user-gpu/template/notification-fd \
	usr/share/spectrum/service/vhost-user-gpu/template/run \
	usr/share/spectrum/service/vhost-user-gpu/template/type \
	usr/share/spectrum/service/vmm/log/run \
	usr/share/spectrum/service/vmm/notification-fd \
	usr/share/spectrum/service/vmm/run \
	usr/share/spectrum/service/vmm/template/log/run \
	usr/share/spectrum/service/vmm/template/notification-fd \
	usr/share/spectrum/service/xdg-desktop-portal-spectrum-host/log/run \
	usr/share/spectrum/service/xdg-desktop-portal-spectrum-host/notification-fd \
	usr/share/spectrum/service/xdg-desktop-portal-spectrum-host/run \
	usr/share/spectrum/service/xdg-desktop-portal-spectrum-host/template/log/run \
	usr/share/spectrum/service/xdg-desktop-portal-spectrum-host/template/notification-fd \
	usr/share/spectrum/service/xdg-desktop-portal-spectrum-host/template/run

DIRS = \
	etc/dbus \
	ext \
	root/.ssh \
	usr/share/spectrum/configs \
	usr/share/spectrum/service/dbus/instance \
	usr/share/spectrum/service/dbus/instances \
	usr/share/spectrum/service/dbus/template/data \
	usr/share/spectrum/service/dbus/template/env \
	usr/share/spectrum/service/vhost-user-fs/instance \
	usr/share/spectrum/service/vhost-user-fs/instances \
	usr/share/spectrum/service/vhost-user-fs/template/data \
	usr/share/spectrum/service/vhost-user-fs/template/env \
	usr/share/spectrum/service/vhost-user-gpu/instance \
	usr/share/spectrum/service/vhost-user-gpu/instances \
	usr/share/spectrum/service/vhost-user-gpu/template/env \
	usr/share/spectrum/service/vmm/instance \
	usr/share/spectrum/service/vmm/instances \
	usr/share/spectrum/service/vmm/template/data \
	usr/share/spectrum/service/vmm/template/env \
	usr/share/spectrum/service/xdg-desktop-portal-spectrum-host/instance \
	usr/share/spectrum/service/xdg-desktop-portal-spectrum-host/instances \
	usr/share/spectrum/service/xdg-desktop-portal-spectrum-host/template/data \
	usr/share/spectrum/service/xdg-desktop-portal-spectrum-host/template/env \
	var

# These are separate because they need to be included, but putting
# them as make dependencies would confuse make.
LINKS = \
	etc/systemd/system-generators/systemd-veritysetup-generator \
	etc/systemd/system/default.target.requires/s6-init-start.service \
	etc/systemd/system/graphical.target.requires/s6-init-start.service \
	etc/systemd/system/multi-user.target.requires/s6-init-start.service \
	usr/share/spectrum/service/vmm/template/run

BUILD_FILES = build/etc/s6-rc/compiled

$(dest): ../../scripts/make-erofs.sh $(PACKAGES_FILE) $(FILES) $(BUILD_FILES) build/empty build/fifo
	( \
	    cat $(PACKAGES_FILE) ;\
	    for file in $(FILES) $(LINKS); do printf '%s\n%s\n' $$file $$file; done ;\
	    for file in $(BUILD_FILES); do printf '%s\n%s\n' $$file $${file#build/}; done ;\
	    printf 'build/empty\n%s\n' $(DIRS) ;\
	) | ../../scripts/make-erofs.sh systemd $@

build/fifo:
	mkdir -p build
	mkfifo -m 0600 $@

build/empty:
	mkdir -p $@

S6_RC_FILES = \
	etc/s6-rc/ok-all/contents \
	etc/s6-rc/ok-all/type \
	etc/s6-rc/sys-vmms/type \
	etc/s6-rc/sys-vmms/up \
	etc/s6-rc/weston/notification-fd \
	etc/s6-rc/weston/run \
	etc/s6-rc/weston/type

# s6-rc-compile's input is a directory, but that doesn't play nice
# with Make, because it won't know to update if some file in the
# directory is changed, or a file is created or removed in a
# subdirectory.  Using the whole source directory could also end up
# including files that aren't intended to be part of the input, like
# temporary editor files or .license files.  So for all these reasons,
# only explicitly listed files are made available to s6-rc-compile.
build/etc/s6-rc/compiled: $(S6_RC_FILES)
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
	mkfs.bcachefs "$$ext" && \
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
	    -append "console=hvc0 systemd.verity=no roothash=$$(< build/rootfs.verity.roothash) intel_iommu=on nokaslr systemd.verity=no" \
	    -device virtio-keyboard \
	    -device virtio-mouse \
	    -device virtio-gpu \
	    -netdev user,id=net0 \
	    -device e1000e,netdev=net0 \
	    -vga none \
	    -device vhost-vsock-pci,guest-cid=3
.PHONY: run
