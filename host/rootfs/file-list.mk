# SPDX-License-Identifier: CC0-1.0
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

FILES = \
	image/etc/fonts/fonts.conf \
	image/etc/fstab \
	image/etc/group \
	image/etc/init \
	image/etc/login \
	image/etc/parse-devname \
	image/etc/passwd \
	image/etc/s6-linux-init/env/WAYLAND_DISPLAY \
	image/etc/s6-linux-init/env/XDG_RUNTIME_DIR \
	image/etc/s6-linux-init/run-image/service/getty-tty1/run \
	image/etc/s6-linux-init/run-image/service/getty-tty2/run \
	image/etc/s6-linux-init/run-image/service/getty-tty3/run \
	image/etc/s6-linux-init/run-image/service/getty-tty4/run \
	image/etc/s6-linux-init/run-image/service/s6-svscan-log/notification-fd \
	image/etc/s6-linux-init/run-image/service/s6-svscan-log/run \
	image/etc/s6-linux-init/run-image/service/serial-getty-generator/run \
	image/etc/s6-linux-init/run-image/service/serial-getty/notification-fd \
	image/etc/s6-linux-init/run-image/service/serial-getty/run \
	image/etc/s6-linux-init/run-image/service/serial-getty/template/run \
	image/etc/s6-linux-init/run-image/service/vm-services/notification-fd \
	image/etc/s6-linux-init/run-image/service/vm-services/run \
	image/etc/s6-linux-init/run-image/service/vm-services/template/data/service/dbus/notification-fd \
	image/etc/s6-linux-init/run-image/service/vm-services/template/data/service/dbus/run \
	image/etc/s6-linux-init/run-image/service/vm-services/template/data/service/vhost-user-fs/notification-fd \
	image/etc/s6-linux-init/run-image/service/vm-services/template/data/service/vhost-user-fs/run \
	image/etc/s6-linux-init/run-image/service/vm-services/template/data/service/vhost-user-gpu/notification-fd \
	image/etc/s6-linux-init/run-image/service/vm-services/template/data/service/vhost-user-gpu/run \
	image/etc/s6-linux-init/run-image/service/vm-services/template/data/service/xdg-desktop-portal-spectrum-host/notification-fd \
	image/etc/s6-linux-init/run-image/service/vm-services/template/data/service/xdg-desktop-portal-spectrum-host/run \
	image/etc/s6-linux-init/run-image/service/vm-services/template/notification-fd \
	image/etc/s6-linux-init/run-image/service/vm-services/template/run \
	image/etc/s6-linux-init/run-image/service/vmm/notification-fd \
	image/etc/s6-linux-init/run-image/service/vmm/run \
	image/etc/s6-linux-init/run-image/service/vmm/template/notification-fd \
	image/etc/s6-linux-init/scripts/rc.init \
	image/etc/udev/rules.d/99-spectrum.rules \
	image/etc/xdg/weston/autolaunch \
	image/etc/xdg/weston/weston.ini \
	image/usr/bin/assign-devices \
	image/usr/bin/create-vm-dependencies \
	image/usr/bin/run-appimage \
	image/usr/bin/run-vmm \
	image/usr/bin/vm-console \
	image/usr/bin/vm-import \
	image/usr/bin/vm-start \
	image/usr/bin/vm-stop \
	image/usr/bin/xdg-open \
	image/usr/libexec/net-add \
	image/usr/share/dbus-1/services/org.freedesktop.portal.Documents.service

LINKS = \
	image/bin \
	image/etc/s6-linux-init/run-image/opengl-driver \
	image/etc/s6-linux-init/run-image/service/vmm/template/run \
	image/lib \
	image/sbin \
	image/usr/bin/systemd-udevd

S6_RC_FILES = \
	image/etc/s6-rc/core/type \
	image/etc/s6-rc/core/up \
	image/etc/s6-rc/ok-all/contents.d/sys-vmms \
	image/etc/s6-rc/ok-all/contents.d/systemd-udevd-coldplug \
	image/etc/s6-rc/ok-all/contents.d/vm-env \
	image/etc/s6-rc/ok-all/type \
	image/etc/s6-rc/static-nodes/type \
	image/etc/s6-rc/static-nodes/up \
	image/etc/s6-rc/sys-vmms/dependencies.d/vmm-env \
	image/etc/s6-rc/sys-vmms/type \
	image/etc/s6-rc/sys-vmms/up \
	image/etc/s6-rc/systemd-udevd-coldplug/dependencies.d/systemd-udevd \
	image/etc/s6-rc/systemd-udevd-coldplug/type \
	image/etc/s6-rc/systemd-udevd-coldplug/up \
	image/etc/s6-rc/systemd-udevd/notification-fd \
	image/etc/s6-rc/systemd-udevd/run \
	image/etc/s6-rc/systemd-udevd/type \
	image/etc/s6-rc/vm-env/contents.d/static-nodes \
	image/etc/s6-rc/vm-env/contents.d/systemd-udevd-coldplug \
	image/etc/s6-rc/vm-env/contents.d/weston \
	image/etc/s6-rc/vm-env/type \
	image/etc/s6-rc/vmm-env/contents.d/core \
	image/etc/s6-rc/vmm-env/contents.d/static-nodes \
	image/etc/s6-rc/vmm-env/contents.d/systemd-udevd-coldplug \
	image/etc/s6-rc/vmm-env/type \
	image/etc/s6-rc/weston/dependencies.d/systemd-udevd-coldplug \
	image/etc/s6-rc/weston/notification-fd \
	image/etc/s6-rc/weston/run \
	image/etc/s6-rc/weston/type
