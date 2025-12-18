// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>
// SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>

#include "lib.h"

#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <arpa/inet.h>
#include <net/if.h>

#include <sys/socket.h>
#include <linux/if_addr.h>
#include <linux/ipv6.h>
#include <linux/rtnetlink.h>

static int setup_server(void)
{
	int fd;

	struct sockaddr_in6 addr = {
		.sin6_family = AF_INET6,
		.sin6_port = htons(1234),
		.sin6_addr = { .s6_addr = { 0xfd, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02 } },
	};

	struct {
		struct nlmsghdr nh;
		struct ifaddrmsg ifa;
		struct rtattr attr;
		struct in6_addr addr;
	} newaddr_req = {
		{
			.nlmsg_len = sizeof newaddr_req,
			.nlmsg_type = RTM_NEWADDR,
			.nlmsg_flags = NLM_F_ACK | NLM_F_REQUEST,
		},
		{
			.ifa_family = AF_INET6,
			.ifa_prefixlen = 128,
			.ifa_flags = IFA_F_NODAD,
			.ifa_index = 1,
		},
		{
			.rta_len = sizeof newaddr_req.attr + sizeof newaddr_req.addr,
			.rta_type = IFA_ADDRESS,
		},
		addr.sin6_addr,
	};

	struct {
		struct nlmsghdr nh;
		struct ifinfomsg ifi;
	} newlink_req = {
		{
			.nlmsg_len = sizeof newlink_req,
			.nlmsg_type = RTM_NEWLINK,
			.nlmsg_flags = NLM_F_ACK | NLM_F_REQUEST,
		},
		{
			.ifi_index = 1,
			.ifi_flags = IFF_UP,
			.ifi_change = IFF_UP,
		},
	};

	struct {
		struct nlmsghdr nh;
		struct nlmsgerr err;
	} res;

	if ((fd = socket(AF_NETLINK, SOCK_DGRAM|SOCK_CLOEXEC, NETLINK_ROUTE)) == -1) {
		perror("socket");
		exit(EXIT_FAILURE);
	}

	if (send(fd, &newaddr_req, sizeof newaddr_req, 0) == -1) {
		perror("send");
		exit(EXIT_FAILURE);
	}

	if (recv(fd, &res, sizeof res, 0) == -1) {
		perror("recv");
		exit(EXIT_FAILURE);
	}

	if (res.err.error) {
		fprintf(stderr, "RTM_NEWADDR: %s", strerror(-res.err.error));
		exit(EXIT_FAILURE);
	}

	if (send(fd, &newlink_req, sizeof newlink_req, 0) == -1) {
		perror("send");
		exit(EXIT_FAILURE);
	}

	if (recv(fd, &res, sizeof res, 0) == -1) {
		perror("recv");
		exit(EXIT_FAILURE);
	}

	if (res.err.error) {
		fprintf(stderr, "RTM_NEWLINK: %s", strerror(-res.err.error));
		exit(EXIT_FAILURE);
	}

	close(fd);

	if ((fd = socket(AF_INET6, SOCK_STREAM|SOCK_CLOEXEC, 0)) == -1) {
		perror("socket");
		exit(EXIT_FAILURE);
	}

	if (bind(fd, &addr, sizeof addr) == -1) {
		perror("bind");
		exit(EXIT_FAILURE);
	}

	if (listen(fd, 1) == -1) {
		perror("listen");
		exit(EXIT_FAILURE);
	}

	return fd;
}

static void expect_connection(int listener)
{
	int conn, r;
	char msg[7];
	size_t len;

	for (;;) {
		len = 0;

		fputs("waiting for server connection\n", stderr);
		if ((conn = accept(listener, nullptr, nullptr)) == -1) {
			perror("accept");
			exit(EXIT_FAILURE);
		}
		fputs("accepted connection!\n", stderr);

		for (;;) {
			r = read(conn, msg + len, sizeof msg - len);
			if (r == -1) {
				perror("read");
				exit(EXIT_FAILURE);
			}
			if (r == 0)
				break;
			len += r;
		}
		close(conn);

		if (memcmp("hello\n", msg, len) || len > 6) {
			fprintf(stderr, "unexpected connection data: %.*s",
			        (int)len, msg);
			exit(EXIT_FAILURE);
		}

		// If connection was disconnect partway through, try again.
		if (len < 6)
			continue;

		return;
	}
}

static void drain_connections(int listener)
{
	int r;
	struct pollfd pollfd = { .fd = listener, .events = POLLIN };

	for (;;) {
		switch (poll(&pollfd, 1, 0)) {
		case -1:
			perror("poll");
			exit(EXIT_FAILURE);
		case 0:
			return;
		}

		if ((r = accept4(listener, nullptr, nullptr, SOCK_CLOEXEC)) == -1) {
			perror("accept");
			exit(EXIT_FAILURE);
		}

		close(r);
	}
}

void test(struct config c)
{
	int server = setup_server();

	struct vm *vm = start_qemu(c);
	start_console_thread(vm, "~ # ");
	wait_for_prompt(vm);

	if (fputs("set -euxo pipefail && "
	          "mkdir /run/mnt && "
	          "mount \"$(findfs UUID=a7834806-2f82-4faf-8ac4-4f8fd8a474ca)\" /run/mnt && "
	          "s6-rc -bu change vmm-env && "
	          "vm-import user /run/mnt/vms /run/mnt/storage && "
	          "vm-start \"$(basename \"$(readlink /run/vm/by-name/user.nc)\")\" && "
	          "tail -Fc +0 /run/log/current /run/vm/by-id/*/serial &\n",
	          vm_console_writer(vm)) == EOF) {
		fputs("error writing to console\n", stderr);
		exit(EXIT_FAILURE);
	}

	expect_connection(server);

	wait_for_prompt(vm);

	if (fputs("s6-svc -wR -r /run/vm/by-name/sys.netvm/service\n",
	          vm_console_writer(vm)) == EOF) {
		fputs("error writing to console\n", stderr);
		exit(EXIT_FAILURE);
	}

	wait_for_prompt(vm);

	drain_connections(server);

	if (fputs("vm-start \"$(basename \"$(readlink /run/vm/by-name/sys.netvm)\")\"\n",
	          vm_console_writer(vm)) == EOF) {
		fputs("error writing to console\n", stderr);
		exit(EXIT_FAILURE);
	}

	expect_connection(server);
}
