# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>

.POSIX:

include ../../../lib/common.mk

prefix = build/host
libdir = $(prefix)/lib
vmdir = $(libdir)/spectrum/vm

VMM = cloud-hypervisor

HOST_BUILD_FILES = \
	$(vmdir)/netvm/blk/root.img \
	$(vmdir)/netvm/vmlinux

all: $(HOST_BUILD_FILES)
.PHONY: all

$(vmdir)/netvm/vmlinux: $(KERNEL)
	mkdir -p $$(dirname $@)
	cp $(KERNEL) $@

$(vmdir)/netvm/blk/root.img: ../../../scripts/make-gpt.sh ../../../scripts/sfdisk-field.awk build/rootfs.erofs
	mkdir -p $$(dirname $@)
	../../../scripts/make-gpt.sh $@.tmp \
	    build/rootfs.erofs:root:ea21da27-0391-48da-9235-9d2ab2ca7844:root
	mv $@.tmp $@

VM_FILES = \
	image/etc/dbus-1/system.conf \
	image/etc/fstab \
	image/etc/init \
	image/etc/mdev.conf \
	image/etc/mdev/iface \
	image/etc/nftables.conf \
	image/etc/passwd \
	image/etc/s6-linux-init/run-image/service/getty-hvc0/run \
	image/etc/s6-linux-init/scripts/rc.init \
	image/etc/sysctl.conf
VM_DIRS = dev etc/s6-linux-init/env run proc sys var/lib/connman

# These are separate because they need to be included, but putting
# them as make dependencies would confuse make.
VM_LINKS = image/bin image/lib image/sbin image/var/run

VM_BUILD_FILES = build/etc/s6-rc

build/empty:
	mkdir -p $@

build/rootfs.erofs: ../../../scripts/make-erofs.sh $(PACKAGES_FILE) $(VM_FILES) $(VM_BUILD_FILES) build/empty
	( \
	    cat $(PACKAGES_FILE) ;\
	    for file in $(VM_FILES) $(VM_LINKS); do printf '%s\n%s\n' $$file "$${file#image/}"; done ;\
	    for file in $(VM_BUILD_FILES); do printf '%s\n%s\n' $$file $${file#build/}; done ;\
	    printf 'build/empty\n%s\n' $(VM_DIRS) ;\
	) | ../../../scripts/make-erofs.sh $@

VM_S6_RC_FILES = \
	image/etc/s6-rc/connman/dependencies.d/dbus \
	image/etc/s6-rc/connman/run \
	image/etc/s6-rc/connman/type \
	image/etc/s6-rc/dbus/notification-fd \
	image/etc/s6-rc/dbus/run \
	image/etc/s6-rc/dbus/type \
	image/etc/s6-rc/mdevd-coldplug/dependencies.d/mdevd \
	image/etc/s6-rc/mdevd-coldplug/type \
	image/etc/s6-rc/mdevd-coldplug/up \
	image/etc/s6-rc/mdevd/notification-fd \
	image/etc/s6-rc/mdevd/run \
	image/etc/s6-rc/mdevd/type \
	image/etc/s6-rc/nftables/type \
	image/etc/s6-rc/nftables/up \
	image/etc/s6-rc/ok-all/contents \
	image/etc/s6-rc/ok-all/type \
	image/etc/s6-rc/sysctl/type \
	image/etc/s6-rc/sysctl/up

build/etc/s6-rc: $(VM_S6_RC_FILES)
	mkdir -p $$(dirname $@)
	rm -rf $@
	set -uo pipefail && dir=$$(mktemp -d) && \
	    { tar -c $(VM_S6_RC_FILES) | tar -C $$dir -x --strip-components 3; } && \
	    s6-rc-compile $@ $$dir; \
	    exit=$$?; rm -r $$dir; exit $$exit

debug:
	$(GDB) -q \
	    -ex 'set substitute-path .. $(LINUX_SRC)' \
	    -ex 'target remote build/gdb.sock' \
	    $(VMLINUX)
.PHONY: debug

start-vhost-user-net:
	mkdir -p build
	../../../scripts/start-passt.elb

run-qemu: $(vmdir)/netvm/blk/root.img
	@../../../scripts/run-qemu.sh -m 256 -cpu max -kernel $(KERNEL) -vga none \
	    -drive file=$(vmdir)/netvm/blk/root.img,if=virtio,format=raw,readonly=on \
	    -append "root=PARTLABEL=root nokaslr" \
	    -gdb unix:build/gdb.sock,server,nowait \
	    -netdev user,id=net0 \
	    -device e1000e,netdev=net0 \
	    -netdev user,id=net1 \
	    -device virtio-net,netdev=net1,mac=02:01:00:00:00:01 \
	    -parallel none \
	    -chardev vc,id=virtiocon0 \
	    -device virtio-serial-pci \
	    -device virtconsole,chardev=virtiocon0
.PHONY: run-qemu

run-cloud-hypervisor: $(vmdir)/netvm/blk/root.img start-vhost-user-net
	rm -f build/vmm.sock
	@../../../scripts/with-taps.elb \
	    ../../../scripts/run-cloud-hypervisor.sh \
	    --api-socket path=build/vmm.sock \
	    --memory size=256M,shared=on \
	    --disk path=$(vmdir)/netvm/blk/root.img,readonly=on \
	    --net vhost_user=on,socket=build/vhost-user-net.sock tap=tap1,mac=02:01:00:00:00:01 \
	    --kernel $(KERNEL) \
	    --cmdline "root=PARTLABEL=root" \
	    --console tty \
	    --serial file=build/serial.log
.PHONY: run-cloud-hypervisor

run-crosvm: $(vmdir)/netvm/blk/root.img
	../../../scripts/with-taps.elb $(CROSVM_RUN) \
	    --disk $(vmdir)/netvm/blk/root.img \
	    -p "console=ttyS0 root=PARTLABEL=root" \
	    --net tap-name=tap0 \
	    --net tap-name=tap1,mac=02:01:00:00:00:01 \
	    --serial type=file,hardware=serial,path=build/serial.log \
	    --serial type=stdout,hardware=virtio-console,stdin=true \
	    $(KERNEL)
.PHONY: run-crosvm

run: run-$(VMM)
.PHONY: run

clean:
	rm -rf build
.PHONY: clean
