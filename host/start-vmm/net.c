// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022-2024 Alyssa Ross <hi@alyssa.is>

#include "ch.h"
#include "net-util.h"

#include <assert.h>
#include <err.h>
#include <errno.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdnoreturn.h>
#include <string.h>
#include <unistd.h>

#include <linux/if_tun.h>

static int setup_tap(const char bridge_name[static 1],
                     const char tap_prefix[static 1],
                     char tap_name[static IFNAMSIZ])
{
	int fd;

	// We assume ≤16-bit pids.
	if (snprintf(tap_name, IFNAMSIZ, "%s%d", tap_prefix, getpid()) < -1)
		return -1;
	if ((fd = tap_open(tap_name, IFF_NO_PI|IFF_VNET_HDR|IFF_TUN_EXCL)) == -1)
		goto out;
	if (bridge_add_if(bridge_name, tap_name) == -1)
		goto fail;
	if (if_up(tap_name) == -1)
		goto fail;

	goto out;
fail:
	close(fd);
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
                            const uint8_t mac[6],
                            char device_id_out[static IFNAMSIZ])
{
	struct net_config net;
	int e;

	memcpy(&net.mac, mac, sizeof net.mac);
	if ((net.fd = setup_tap(bridge_name, "router", net.id)) == -1)
		return -1;

	e = ch_add_net(router_vm_dir, &net);
	close(net.fd);
	if (!e) {
		// net.id is NUL-terminated and can't be longer than
		// device_id_out.
		// NOLINTNEXTLINE(clang-analyzer-security.insecureAPI.strcpy)
		strcpy(device_id_out, net.id);
		return 0;
	}
	errno = e;
	return -1;
}

[[gnu::nonnull]]
static int router_net_cleanup(pid_t pid, const struct vm_dir *vm_dir,
                              const char device_id[static 1])
{
	int e;
	char name[IFNAMSIZ], newname[IFNAMSIZ], brname[IFNAMSIZ];

	if ((e = ch_remove_device(vm_dir, device_id))) {
		errno = e;
		return -1;
	}

	// Work around cloud-hypervisor not closing taps it's no
	// longer using by freeing up the name.
	//
	// We assume ≤16-bit pids.
	snprintf(name, sizeof name, "router%d", pid);
	snprintf(newname, sizeof newname, "_dead%d", pid);
	snprintf(brname, sizeof brname, "br%d", pid);

	if (bridge_remove_if(brname, name) == -1)
		warn("removing %s from %s", name, brname);

	if (if_down(name) == -1)
		return -1;
	return if_rename(name, newname);
}

static int bridge_cleanup(pid_t pid)
{
	char name[IFNAMSIZ];
	snprintf(name, sizeof name, "br%d", pid);
	return bridge_delete(name);
}

[[gnu::nonnull]]
static noreturn void exit_listener_main(int fd, pid_t pid,
                                        const struct vm_dir *router_vm_dir,
                                        const char router_device_id[static 1])
{
	// Wait for the other end of the pipe to be closed.
	int status = EXIT_SUCCESS;
	struct pollfd pollfd = { .fd = fd, .events = 0, .revents = 0 };
	while (poll(&pollfd, 1, -1) == -1) {
		if (errno == EINTR || errno == EWOULDBLOCK)
			continue;

		err(1, "poll");
	}
	assert(pollfd.revents == POLLERR);

	if (router_net_cleanup(pid, router_vm_dir, router_device_id) == -1) {
		warn("cleaning up router tap");
		status = EXIT_FAILURE;
	}
	if (bridge_cleanup(pid) == -1) {
		warn("cleaning up bridge");
		status = EXIT_FAILURE;
	}

	exit(status);
}

[[gnu::nonnull]]
static int exit_listener_setup(const struct vm_dir *router_vm_dir,
                               const char router_device_id[static 1])
{
	pid_t pid = getpid();
	int fd[2];

	if (pipe(fd) == -1)
		return -1;

	switch (fork()) {
	case -1:
		close(fd[0]);
		close(fd[1]);
		return -1;
	case 0:
		close(fd[0]);
		exit_listener_main(fd[1], pid, router_vm_dir, router_device_id);
	default:
		close(fd[1]);
		return 0;
	}
}

[[gnu::nonnull]]
struct net_config net_setup(const struct vm_dir *router_vm_dir)
{
	struct net_config r = { .fd = -1, .mac = { 0 } };
	char bridge_name[IFNAMSIZ], router_device_id[IFNAMSIZ] = { 0 };
	pid_t pid = getpid();
	// We assume ≤16-bit pids.
	uint8_t router_mac[6] = { 0x0A, 0xB3, 0xEC, 0x80, pid >> 8, pid };

	memcpy(r.mac, router_mac, 6);
	r.mac[3] = 0x00;

	if (snprintf(bridge_name, sizeof bridge_name, "br%d", pid) < -1)
		return r;

	if (bridge_add(bridge_name) == -1)
		return r;
	if (if_up(bridge_name) == -1)
		goto fail_bridge;

	if ((r.fd = client_net_setup(bridge_name, r.id)) == -1)
		goto fail_bridge;

	if (router_net_setup(bridge_name, router_vm_dir, router_mac,
	                     router_device_id) == -1)
		goto fail_bridge;

	// Set up a process that will listen for this process dying,
	// and remove the interface from the netvm, and delete the
	// bridge.
	if (exit_listener_setup(router_vm_dir, router_device_id) == -1)
		goto fail_bridge;

	return r;

fail_bridge:
	bridge_delete(bridge_name);
	close(r.fd);
	r.fd = -1;
	return r;
}
