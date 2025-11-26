# SPDX-License-Identifier: CC0-1.0
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

FILES = \
	image/etc/dbus-1/session.conf \
	image/etc/flatpak/installations.d/extra.conf \
	image/etc/fstab \
	image/etc/group \
	image/etc/mdev.conf \
	image/etc/mdev/iface \
	image/etc/mdev/listen \
	image/etc/mdev/virtiofs \
	image/etc/mdev/wait \
	image/etc/nsswitch.conf \
	image/etc/passwd \
	image/etc/pipewire/pipewire.conf \
	image/etc/resolv.conf \
	image/etc/s6-linux-init/env/DBUS_SESSION_BUS_ADDRESS \
	image/etc/s6-linux-init/env/DISPLAY \
	image/etc/s6-linux-init/env/GTK_USE_PORTAL \
	image/etc/s6-linux-init/env/NIX_XDG_DESKTOP_PORTAL_DIR \
	image/etc/s6-linux-init/env/WAYLAND_DISPLAY \
	image/etc/s6-linux-init/env/XDG_DESKTOP_PORTAL_SPECTRUM_GUEST_PORT \
	image/etc/s6-linux-init/env/XDG_RUNTIME_DIR \
	image/etc/s6-linux-init/run-image/service/getty-hvc0/run \
	image/etc/s6-linux-init/run-image/service/s6-linux-init-shutdownd/notification-fd \
	image/etc/s6-linux-init/run-image/service/s6-linux-init-shutdownd/run \
	image/etc/s6-linux-init/scripts/rc.init \
	image/etc/s6-linux-init/scripts/rc.shutdown \
	image/etc/s6-linux-init/scripts/rc.shutdown.final \
	image/etc/wireplumber/wireplumber.conf.d/99_spectrum.conf \
	image/etc/xdg/xdg-desktop-portal/portals.conf \
	image/usr/bin/init

LINKS = \
	image/bin \
	image/etc/ssl/certs/ca-certificates.crt \
	image/sbin

S6_RC_FILES = \
	image/etc/s6-rc/app/dependencies.d/dbus \
	image/etc/s6-rc/app/dependencies.d/pipewire \
	image/etc/s6-rc/app/dependencies.d/wayland-proxy-virtwl \
	image/etc/s6-rc/app/run \
	image/etc/s6-rc/app/type \
	image/etc/s6-rc/dbus-vsock/notification-fd \
	image/etc/s6-rc/dbus-vsock/run \
	image/etc/s6-rc/dbus-vsock/type \
	image/etc/s6-rc/dbus/dependencies.d/dbus-vsock \
	image/etc/s6-rc/dbus/notification-fd \
	image/etc/s6-rc/dbus/run \
	image/etc/s6-rc/dbus/type \
	image/etc/s6-rc/mdevd-coldplug/dependencies.d/mdevd \
	image/etc/s6-rc/mdevd-coldplug/type \
	image/etc/s6-rc/mdevd-coldplug/up \
	image/etc/s6-rc/mdevd/notification-fd \
	image/etc/s6-rc/mdevd/run \
	image/etc/s6-rc/mdevd/type \
	image/etc/s6-rc/ok-all/contents.d/app \
	image/etc/s6-rc/ok-all/contents.d/mdevd-coldplug \
	image/etc/s6-rc/ok-all/contents.d/wireplumber \
	image/etc/s6-rc/ok-all/type \
	image/etc/s6-rc/pipewire/notification-fd \
	image/etc/s6-rc/pipewire/run \
	image/etc/s6-rc/pipewire/type \
	image/etc/s6-rc/wayland-proxy-virtwl/notification-fd \
	image/etc/s6-rc/wayland-proxy-virtwl/run \
	image/etc/s6-rc/wayland-proxy-virtwl/type \
	image/etc/s6-rc/wireplumber/dependencies.d/dbus \
	image/etc/s6-rc/wireplumber/dependencies.d/pipewire \
	image/etc/s6-rc/wireplumber/run \
	image/etc/s6-rc/wireplumber/type
