# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>

.POSIX:

include ../../../lib/common.mk
include file-list.mk

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

DIRS = dev etc/s6-linux-init/env proc run sys var/lib/connman

BUILD_FILES = build/etc/s6-rc

build/empty:
	mkdir -p $@

build/rootfs.erofs: ../../../scripts/make-erofs.sh $(PACKAGES_FILE) $(FILES) $(BUILD_FILES) build/empty file-list.mk
	set -euo pipefail; \
	{ \
	    cat $(PACKAGES_FILE) ;\
	    for file in $(FILES) $(LINKS); do printf '%s\n%s\n' $$file "$${file#image/}"; done ;\
	    for file in $(BUILD_FILES); do printf '%s\n%s\n' $$file $${file#build/}; done ;\
	    printf 'build/empty\n%s\n' $(DIRS) ;\
	} | ../../../scripts/make-erofs.sh $@

build/etc/s6-rc: $(S6_RC_FILES) file-list.mk
	mkdir -p $$(dirname $@)
	rm -rf $@
	set -uo pipefail && dir=$$(mktemp -d) && \
	    { tar -c $(S6_RC_FILES) | tar -C $$dir -x --strip-components 3; } && \
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
