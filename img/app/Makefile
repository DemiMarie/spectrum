# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie

.POSIX:

include ../../lib/common.mk
include file-list.mk

prefix = build/host
libdir = $(prefix)/lib
imgdir = $(libdir)/spectrum/img

VMM = cloud-hypervisor

HOST_BUILD_FILES = \
	$(imgdir)/appvm/blk/root.img \
	$(imgdir)/appvm/vmlinux

all: $(HOST_BUILD_FILES)
.PHONY: all

$(imgdir)/appvm/vmlinux: $(KERNEL)
	mkdir -p $$(dirname $@)
	cp $(KERNEL) $@

$(imgdir)/appvm/blk/root.img: ../../scripts/make-gpt.sh ../../scripts/make-gpt.bash ../../scripts/sfdisk-field.awk build/rootfs.erofs
	mkdir -p $$(dirname $@)
	../../scripts/make-gpt.sh $@.tmp \
	    build/rootfs.erofs:root:5460386f-2203-4911-8694-91400125c604:root
	mv $@.tmp $@

DIRS = dev run proc sys tmp \
	etc/s6-linux-init/run-image/service \
	etc/s6-linux-init/run-image/user \
	etc/s6-linux-init/run-image/wait
FIFOS = etc/s6-linux-init/run-image/service/s6-linux-init-shutdownd/fifo

BUILD_FILES = build/etc/s6-rc

build/fifo:
	mkdir -p build
	mkfifo -m 0600 $@

build/empty:
	mkdir -p $@

build/rootfs.erofs: ../../scripts/make-erofs.sh $(PACKAGES_FILE) $(FILES) $(BUILD_FILES) build/empty build/fifo file-list.mk
	set -euo pipefail; \
	{ \
	    cat $(PACKAGES_FILE) ;\
	    for file in $(FILES) $(LINKS); do printf '%s\n%s\n' $$file "$${file#image/}"; done ;\
	    for file in $(BUILD_FILES); do printf '%s\n%s\n' $$file $${file#build/}; done ;\
	    printf 'build/empty\n%s\n' $(DIRS) ;\
	    printf 'build/fifo\n%s\n' $(FIFOS) ;\
	} | ../../scripts/make-erofs.sh $@


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

start-vhost-user-gpu:
	rm -f build/vhost-user-gpu.sock
	$(CROSVM_DEVICE_GPU) \
	    --socket build/vhost-user-gpu.sock \
	    --wayland-sock "$$XDG_RUNTIME_DIR/$$WAYLAND_DISPLAY" \
	    --params '{"context-types":"cross-domain"}' &
	while ! [ -S build/vhost-user-gpu.sock ] && sleep .1; do :; done
.PHONY: start-vhost-user-gpu

start-vhost-user-net:
	mkdir -p build
	../../scripts/start-passt.elb

start-virtiofsd: scripts/start-virtiofsd.elb
	mkdir -p build
	scripts/start-virtiofsd.elb
.PHONY: start-virtiofsd

run-qemu: $(imgdir)/appvm/blk/root.img start-vhost-user-net start-virtiofsd
	@../../scripts/run-qemu.sh -m 256 -cpu max -kernel $(KERNEL) -vga none \
	    -drive file=$(imgdir)/appvm/blk/root.img,if=virtio,format=raw,readonly=on \
	    -append "root=PARTLABEL=root nokaslr" \
	    -gdb unix:build/gdb.sock,server,nowait \
	    -chardev socket,id=vhost-user-net,path=build/vhost-user-net.sock \
	    -netdev vhost-user,id=net0,chardev=vhost-user-net \
	    -device virtio-net,netdev=net0,mac=02:00:00:00:00:01 \
	    -chardev socket,id=virtiofsd,path=build/virtiofsd.sock \
	    -device vhost-user-fs-pci,chardev=virtiofsd,tag=virtiofs0 \
	    -device virtio-gpu-rutabaga-pci,cross-domain=on,hostmem=8G \
	    -audio driver=pipewire,model=virtio \
	    -object memory-backend-memfd,id=mem,size=256M,share=on \
	    -numa node,memdev=mem \
	    -device vhost-vsock-pci,guest-cid=3 \
	    -parallel none \
	    -chardev vc,id=virtiocon0 \
	    -device virtio-serial-pci \
	    -device virtconsole,chardev=virtiocon0
.PHONY: run-qemu

run-cloud-hypervisor: $(imgdir)/appvm/blk/root.img start-vhost-user-gpu start-vhost-user-net start-virtiofsd
	rm -f build/vmm.sock build/vsock.sock
	@../../scripts/run-cloud-hypervisor.sh \
	    --api-socket path=build/vmm.sock \
	    --memory size=1G,shared=on \
	    --disk path=$(imgdir)/appvm/blk/root.img,readonly=on \
	    --fs tag=virtiofs0,socket=build/virtiofsd.sock \
	    --gpu socket=build/vhost-user-gpu.sock \
	    --vsock cid=3,socket=build/vsock.sock \
	    --net mac=02:00:00:00:00:01,vhost_user=on,socket=build/vhost-user-net.sock \
	    --kernel $(KERNEL) \
	    --cmdline "root=PARTLABEL=root" \
	    --console tty \
	    --serial file=build/serial.log
.PHONY: run-cloud-hypervisor

run-crosvm: $(imgdir)/appvm/blk/root.img start-vhost-user-gpu start-virtiofsd
	../../scripts/with-taps.elb $(CROSVM_RUN) \
	    --disk $(imgdir)/appvm/blk/root.img \
	    -p "console=ttyS0 root=PARTLABEL=root" \
	    --net tap-name=tap0,mac=02:00:00:00:00:01 \
	    --vhost-user fs,socket=build/virtiofsd.sock \
	    --vhost-user gpu,socket=build/vhost-user-gpu.sock \
	    --vsock cid=3 \
	    --serial type=file,hardware=serial,path=build/serial.log \
	    --serial type=stdout,hardware=virtio-console,stdin=true \
	    $(KERNEL)
.PHONY: run-crosvm

run: run-$(VMM)
.PHONY: run

clean:
	rm -rf build
.PHONY: clean
