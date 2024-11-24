// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022, 2024 Alyssa Ross <hi@alyssa.is>

#include "net-util.h"

#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

#include <sys/ioctl.h>

#include <linux/if_tun.h>

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
