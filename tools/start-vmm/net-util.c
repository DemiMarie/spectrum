// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022, 2024 Alyssa Ross <hi@alyssa.is>

#include "net-util.h"

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

#include <sys/ioctl.h>

#include <linux/if_tun.h>
#include <linux/sockios.h>

// ifr_name doesn't have to be null terminated.
#pragma GCC diagnostic ignored "-Wstringop-truncation"

int if_up(const char name[static 1])
{
	struct ifreq ifr;
	int fd, e, r = -1;

	if ((fd = socket(AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0)) == -1)
		return -1;

	strncpy(ifr.ifr_name, name, IFNAMSIZ);
	if (ioctl(fd, SIOCGIFFLAGS, &ifr) == -1)
		goto out;
	ifr.ifr_flags |= IFF_UP;
	r = ioctl(fd, SIOCSIFFLAGS, &ifr);
out:
	e = errno;
	close(fd);
	errno = e;
	return r;
}

int if_down(const char name[static 1])
{
	struct ifreq ifr;
	int fd, e, r = -1;

	if ((fd = socket(AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0)) == -1)
		return -1;

	strncpy(ifr.ifr_name, name, IFNAMSIZ);
	if (ioctl(fd, SIOCGIFFLAGS, &ifr) == -1)
		goto out;
	ifr.ifr_flags &= ~IFF_UP;
	r = ioctl(fd, SIOCSIFFLAGS, &ifr);
out:
	e = errno;
	close(fd);
	errno = e;
	return r;
}

int bridge_add(const char name[static 1])
{
	int fd, e, r;

	if (strnlen(name, IFNAMSIZ) == IFNAMSIZ) {
		errno = ENAMETOOLONG;
		return -1;
	}

	if (strchr(name, '%')) {
		errno = EINVAL;
		return -1;
	}

	if ((fd = socket(AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0)) == -1)
		return -1;
	r = ioctl(fd, SIOCBRADDBR, name);
	e = errno;
	close(fd);
	errno = e;
	return r;
}

int bridge_add_if(const char brname[static 1], const char ifname[static 1])
{
	struct ifreq ifr;
	int fd, e, r;

	strncpy(ifr.ifr_name, brname, IFNAMSIZ);
	if (!(ifr.ifr_ifindex = if_nametoindex(ifname)))
		return -1;

	if ((fd = socket(AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0)) == -1)
		return -1;

	r = ioctl(fd, SIOCBRADDIF, &ifr);
	e = errno;
	close(fd);
	errno = e;
	return r;
}

int bridge_delete(const char name[static 1])
{
	int fd, e, r;

	if (if_down(name) == -1)
		warn("setting %s down", name);

	if ((fd = socket(AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0)) == -1)
		return -1;

	r = ioctl(fd, SIOCBRDELBR, name);
	e = errno;
	close(fd);
	errno = e;
	return r;
}

int tap_open(char name[static IFNAMSIZ], int flags)
{
	struct ifreq ifr;
	int fd, e;

	if (strnlen(name, IFNAMSIZ) == IFNAMSIZ) {
		errno = ENAMETOOLONG;
		return -1;
	}

	strncpy(ifr.ifr_name, name, IFNAMSIZ - 1);
	ifr.ifr_flags = IFF_TAP|flags;

	if ((fd = open("/dev/net/tun", O_RDWR)) == -1)
		return -1;
	if (ioctl(fd, TUNSETIFF, &ifr) == -1) {
		e = errno;
		close(fd);
		errno = e;
		return -1;
	}

	strncpy(name, ifr.ifr_name, IFNAMSIZ);
	return fd;
}

int tap_set_persist(int fd, bool persist)
{
	return ioctl(fd, TUNSETPERSIST, persist);
}
