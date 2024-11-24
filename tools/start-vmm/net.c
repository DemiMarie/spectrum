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

static int setup_tap(const char bridge_name[static 1],
                     const char tap_prefix[static 1],
                     const char name[static 1], int name_len,
                     char tap_name[static IFNAMSIZ])
{
	int fd, e;

	if (snprintf(tap_name, IFNAMSIZ, "%s-%*s", tap_prefix, name_len, name) < 0)
		return -1;
	if ((fd = tap_open(tap_name, IFF_NO_PI|IFF_VNET_HDR)) == -1)
		goto out;
	if (tap_set_persist(fd, true) == -1)
		goto fail;
	if (bridge_add_if(bridge_name, tap_name) == -1 && errno != EBUSY)
		goto fail;
	if (if_up(tap_name) == -1)
		goto fail;

	goto out;
fail:
	e = errno;
	close(fd);
	errno = e;
	fd = -1;
out:
	return fd;
}

static int client_net_setup(const char bridge_name[static 1],
                            const char name[static 1], int name_len,
                            char tap_name[static IFNAMSIZ])
{
	return setup_tap(bridge_name, "client", name, name_len, tap_name);
}

[[gnu::nonnull]]
static int router_net_setup(const char bridge_name[static 1],
                            const char name[static 1], int name_len,
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
	if ((net.fd = setup_tap(bridge_name, "router", name, name_len,
	                        tap_name)) == -1)
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
	char bridge_name[IFNAMSIZ];

	if (snprintf(bridge_name, sizeof bridge_name, "br-%*s", name_len, name) < 0)
		return r;

	if (bridge_add(bridge_name) == -1 && errno != EEXIST)
		return r;
	if (if_up(bridge_name) == -1)
		goto fail_bridge;

	if ((r.fd = client_net_setup(bridge_name, name, name_len, r.id)) == -1)
		goto fail_bridge;

	if (!(client_index = htonl(if_nametoindex(r.id))))
		goto fail_bridge;

	router_mac[0] = 0x02; // IEEE 802c administratively assigned
	router_mac[1] = 0x01; // Spectrum router
	memcpy(&router_mac[2], &client_index, 4);

	if (router_net_setup(bridge_name, name, name_len, router_vm_dir,
	                     router_mac) == -1)
		goto fail_bridge;

	memcpy(r.mac, router_mac, sizeof r.mac);
	r.mac[1] = 0x00; // Spectrum client

	return r;

fail_bridge:
	bridge_delete(bridge_name);
	e = errno;
	close(r.fd);
	errno = e;
	r.fd = -1;
	return r;
}
