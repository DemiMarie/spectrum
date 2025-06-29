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

#include <linux/if_tun.h>

static int setup_tap(const char bridge_name[static 1],
                     const char tap_prefix[static 1],
                     char tap_name[static IFNAMSIZ])
{
	int fd, e;

	// We assume ≤16-bit pids.
	if (snprintf(tap_name, IFNAMSIZ, "%s%d", tap_prefix, getpgrp()) < 0)
		return -1;
	if ((fd = tap_open(tap_name, IFF_NO_PI|IFF_VNET_HDR|IFF_TUN_EXCL)) == -1)
		goto out;
	if (bridge_add_if(bridge_name, tap_name) == -1)
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
                            char tap_name[static IFNAMSIZ])
{
	return setup_tap(bridge_name, "client", tap_name);
}

[[gnu::nonnull]]
static int router_net_setup(const char bridge_name[static 1],
                            const struct vm_dir *router_vm_dir,
                            const uint8_t mac[6])
{
	struct net_config net;
	int e;

	memcpy(&net.mac, mac, sizeof net.mac);
	if ((net.fd = setup_tap(bridge_name, "router", net.id)) == -1)
		return -1;

	e = ch_add_net(router_vm_dir, &net);
	close(net.fd);
	if (!e)
		return 0;
	errno = e;
	return -1;
}

[[gnu::nonnull]]
struct net_config net_setup(const struct vm_dir *router_vm_dir)
{
	int e;
	struct net_config r = { .fd = -1, .mac = { 0 } };
	char bridge_name[IFNAMSIZ];
	pid_t pgrp = getpgrp();
	// We assume ≤16-bit pids.
	uint8_t router_mac[6] = { 0x0A, 0xB3, 0xEC, 0x80, pgrp >> 8, pgrp };

	memcpy(r.mac, router_mac, 6);
	r.mac[3] = 0x00;

	if (snprintf(bridge_name, sizeof bridge_name, "br%d", pgrp) < 0)
		return r;

	if (bridge_add(bridge_name) == -1)
		return r;
	if (if_up(bridge_name) == -1)
		goto fail_bridge;

	if ((r.fd = client_net_setup(bridge_name, r.id)) == -1)
		goto fail_bridge;

	if (router_net_setup(bridge_name, router_vm_dir, router_mac) == -1)
		goto fail_bridge;

	return r;

fail_bridge:
	bridge_delete(bridge_name);
	e = errno;
	close(r.fd);
	errno = e;
	r.fd = -1;
	return r;
}
