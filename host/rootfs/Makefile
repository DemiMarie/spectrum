# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

.POSIX:

include ../../lib/common.mk
include file-list.mk

ROOT_FS = build

DIRS = \
	boot \
	dev \
	etc/s6-linux-init/env \
	etc/s6-linux-init/run-image/configs \
	etc/s6-linux-init/run-image/sd-notify-wrapper \
	etc/s6-linux-init/run-image/service/serial-getty/instance \
	etc/s6-linux-init/run-image/service/serial-getty/instances \
	etc/s6-linux-init/run-image/service/vm-services/instance \
	etc/s6-linux-init/run-image/service/vm-services/instances \
	etc/s6-linux-init/run-image/service/vm-services/template/data/service/dbus/data \
	etc/s6-linux-init/run-image/service/vm-services/template/data/service/dbus/env \
	etc/s6-linux-init/run-image/service/vm-services/template/data/service/vhost-user-fs/data \
	etc/s6-linux-init/run-image/service/vm-services/template/data/service/vhost-user-fs/env \
	etc/s6-linux-init/run-image/service/vm-services/template/data/service/vhost-user-gpu/env \
	etc/s6-linux-init/run-image/service/vm-services/template/data/service/xdg-desktop-portal-spectrum-host/data \
	etc/s6-linux-init/run-image/service/vm-services/template/data/service/xdg-desktop-portal-spectrum-host/env \
	etc/s6-linux-init/run-image/service/vmm/instance \
	etc/s6-linux-init/run-image/service/vmm/instances \
	etc/s6-linux-init/run-image/service/vmm/template/data \
	etc/s6-linux-init/run-image/service/vmm/template/env \
	etc/s6-linux-init/run-image/user \
	etc/s6-linux-init/run-image/vm/by-id \
	etc/s6-linux-init/run-image/vm/by-name \
	ext \
	home \
	proc \
	run \
	sys \
	tmp

FIFOS = \
	etc/s6-linux-init/run-image/service/s6-svscan-log/fifo \
	etc/s6-linux-init/run-image/service/s6-linux-init-shutdownd/fifo

BUILD_FILES = build/etc/s6-rc build/etc/os-release build/etc/update-url

# This rule produces three files but Make only (portably)
# supports one output per rule.  Instead of resorting to temporary
# files, a timestamp file is created as the last step.  The actual
# outputs are produced as side-effects.
build/verity-timestamp: $(ROOT_FS_IMAGE)
	mkdir -p build
	$(VERITYSETUP) format \
		--root-hash-file $(ROOT_FS_VERITY_ROOTHASH) \
		-- $(ROOT_FS_IMAGE) $(ROOT_FS_VERITY)
# Add trailing newline so that the read < $(ROOT_FS_VERITY_ROOTHASH) succeeds.
# Without the trailing newline it assumes a premature EOF happened and returns
# a nonzero status.
	echo >> $(ROOT_FS_VERITY_ROOTHASH)
	touch -- $@
$(ROOT_FS_VERITY_ROOTHASH) $(ROOT_FS_VERITY): build/verity-timestamp

$(ROOT_FS_IMAGE): ../../scripts/make-erofs.sh $(PACKAGES_FILE) $(FILES) $(BUILD_FILES) build/empty build/fifo file-list.mk
	mkdir -p $(ROOT_FS) && \
	{ \
	    cat $(PACKAGES_FILE) ;\
	    printf '%s\n%s\n' "$$UPDATE_SIGNING_KEY" /etc/systemd/import-pubring.gpg; \
	    for file in $(FILES) $(LINKS); do printf '%s\n%s\n' $$file "$${file#image/}"; done ;\
	    for file in $(BUILD_FILES); do printf '%s\n%s\n' $$file $${file#build/}; done ;\
	    printf 'build/empty\n%s\n' $(DIRS) ;\
	    printf 'build/fifo\n%s\n' $(FIFOS) ;\
	} | ../../scripts/make-erofs.sh $@

build/etc/update-url:
	mkdir -p build/etc
	# might have metacharacters, so avoid interpolation
	printf %s\\n "$${UPDATE_URL:?'update URL empty or missing'}" > build/etc/update-url

build/etc/os-release:
	mkdir -p build/etc
	sed 's/@VERSION@/$(VERSION)/g' < os-release.in > build/etc/os-release

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

build/live.img: ../../scripts/format-uuid.awk ../../scripts/make-gpt.sh ../../scripts/sfdisk-field.awk build/verity-timestamp $(ROOT_FS_IMAGES)
	../../scripts/make-gpt.sh $@.tmp \
	    $(ROOT_FS_VERITY):verity:$$(awk -f ../../scripts/format-uuid.awk "$$(dd if=$(ROOT_FS_VERITY_ROOTHASH) bs=32 skip=1 count=1 status=none)"):Spectrum_'$(VERSION).verity' \
	    $(ROOT_FS_IMAGE):root:$$(awk -f ../../scripts/format-uuid.awk "$$(head -c 32 $(ROOT_FS_VERITY_ROOTHASH))"):Spectrum_'$(VERSION)'
	mv $@.tmp $@

debug:
	$(GDB) -q \
	    -ex 'set substitute-path .. $(LINUX_SRC)' \
	    -ex 'target remote build/gdb.sock' \
	    $(VMLINUX)
.PHONY: debug

run: build/live.img $(ROOTFS_VERITY_ROOTHASH)
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
	    -append "earlycon console=hvc0 roothash=$$(< $(ROOT_FS_VERITY_ROOTHASH)) intel_iommu=on nokaslr" \
	    -device virtio-keyboard \
	    -device virtio-mouse \
	    -device virtio-gpu \
	    -netdev user,id=net0 \
	    -device e1000e,netdev=net0 \
	    -vga none \
	    -device vhost-vsock-pci,guest-cid=3
.PHONY: run
