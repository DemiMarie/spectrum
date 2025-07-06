// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022-2024 Alyssa Ross <hi@alyssa.is>

#include "ch.h"
#include "net-util.h"

#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <arpa/inet.h>

#include <linux/if_tun.h>

static int get_tap_name(char tap_name[static IFNAMSIZ],
                        const char tap_prefix[static 1],
                        const char name[static 1], int name_len)
{
	int r = snprintf(tap_name, IFNAMSIZ, "%s-%*s", tap_prefix, name_len, name);
	if (r >= IFNAMSIZ)
		errno = ENAMETOOLONG;
	return r < 0 || r >= IFNAMSIZ ? -1 : 0;
}

struct net_config net_setup(const char name[static 1], int name_len)
{
	int e;
	unsigned int client_index;
	struct net_config r = { .fd = -1, .mac = { 0 } };

	if ((get_tap_name(r.id, "client", name, name_len)) == -1)
		return r;

	if (!(client_index = htonl(if_nametoindex(r.id))))
		return r;

	if ((r.fd = tap_open(r.id, IFF_NO_PI|IFF_VNET_HDR)) == -1)
		goto fail_close;

	r.mac[0] = 0x02; // IEEE 802c administratively assigned
	r.mac[1] = 0x00; // Spectrum client
	memcpy(&r.mac[2], &client_index, 4);

	return r;

fail_close:
	e = errno;
	close(r.fd);
	errno = e;
	r.fd = -1;
	return r;
}
