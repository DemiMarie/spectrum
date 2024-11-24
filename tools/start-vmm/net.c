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

[[gnu::nonnull]]
static int router_net_setup(const char name[static 1], int name_len,
                            const struct vm_dir *router_vm_dir,
                            const uint8_t mac[6])
{
	struct net_config net;
	char tap_name[IFNAMSIZ];
	int e;

	memcpy(&net.mac, mac, sizeof net.mac);
	e = snprintf(net.id, sizeof net.id, "client%d", getpgrp());
	if (e > 0 && (size_t)e >= sizeof net.id)
		errno = ENAMETOOLONG;
	if (e < 0 || (size_t)e >= sizeof net.id)
		return -1;

	if (get_tap_name(tap_name, "router", name, name_len) == -1)
		return -1;
	if ((net.fd = tap_open(tap_name, IFF_NO_PI|IFF_VNET_HDR)) == -1)
		return errno == EBUSY ? 0 : -1;

	e = ch_add_net(router_vm_dir, &net);
	close(net.fd);
	if (!e)
		return 0;
	errno = e;
	return -1;
}

[[gnu::nonnull]]
struct net_config net_setup(const char name[static 1], int name_len,
                            const struct vm_dir *router_vm_dir)
{
	int e;
	uint8_t router_mac[6];
	unsigned int client_index;
	struct net_config r = { .fd = -1, .mac = { 0 } };

	if ((get_tap_name(r.id, "client", name, name_len)) == -1)
		return r;

	if (!(client_index = htonl(if_nametoindex(r.id))))
		return r;

	router_mac[0] = 0x02; // IEEE 802c administratively assigned
	router_mac[1] = 0x01; // Spectrum router
	memcpy(&router_mac[2], &client_index, 4);

	if ((r.fd = tap_open(r.id, IFF_NO_PI|IFF_VNET_HDR)) == -1)
		goto fail_close;

	if (router_net_setup(name, name_len, router_vm_dir, router_mac) == -1)
		goto fail_close;

	memcpy(r.mac, router_mac, sizeof r.mac);
	r.mac[1] = 0x00; // Spectrum client

	return r;

fail_close:
	e = errno;
	close(r.fd);
	errno = e;
	r.fd = -1;
	return r;
}
