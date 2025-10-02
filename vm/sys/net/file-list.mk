# SPDX-License-Identifier: CC0-1.0
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

FILES = \
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

LINKS = \
	image/bin \
	image/lib \
	image/sbin \
	image/var/run

S6_RC_FILES = \
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
	image/etc/s6-rc/ok-all/contents.d/mdevd-coldplug \
	image/etc/s6-rc/ok-all/contents.d/sysctl \
	image/etc/s6-rc/ok-all/type \
	image/etc/s6-rc/sysctl/type \
	image/etc/s6-rc/sysctl/up
