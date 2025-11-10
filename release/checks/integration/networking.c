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

#include <sys/ioctl.h>
#include <linux/ipv6.h>

static int setup_server(void)
{
	int fd;
	struct ifreq ifr;
	struct in6_ifreq ifr6;

	struct sockaddr_in6 addr = {
		.sin6_family = AF_INET6,
		.sin6_port = htons(1234),
		.sin6_addr = { .s6_addr = { 0xfd, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02 } },
	};

	sprintf(ifr.ifr_name, "lo");

	ifr6.ifr6_ifindex = 1;
	ifr6.ifr6_addr = addr.sin6_addr;
	ifr6.ifr6_prefixlen = 128;

	if ((fd = socket(AF_INET6, SOCK_STREAM|SOCK_CLOEXEC, 0)) == -1) {
		perror("socket");
		exit(EXIT_FAILURE);
	}

	if (ioctl(fd, SIOCGIFFLAGS, &ifr) == -1) {
		perror("SIOCGIFFLAGS");
		exit(EXIT_FAILURE);
	}

	ifr.ifr_flags |= IFF_UP;
	if (ioctl(fd, SIOCSIFFLAGS, &ifr) == -1) {
		perror("SIOCSIFFLAGS");
		exit(EXIT_FAILURE);
	}

	if (ioctl(fd, SIOCSIFADDR, &ifr6) == -1) {
		perror("SIOCSIFADDR");
		exit(EXIT_FAILURE);
	}

	if ((fd = socket(AF_INET6, SOCK_STREAM|SOCK_CLOEXEC, 0)) == -1) {
		perror("socket");
		exit(EXIT_FAILURE);
	}

	int tries = 0;
	while (bind(fd, &addr, sizeof addr) == -1) {
		perror("bind");
		if (tries++ >= 5)
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
	          "vm-import user /run/mnt/vms && "
	          "vm-start user.nc && "
	          "tail -Fc +0 /run/log/current /run/*.log &\n",
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

	if (fputs("vm-start sys.netvm\n",
	          vm_console_writer(vm)) == EOF) {
		fputs("error writing to console\n", stderr);
		exit(EXIT_FAILURE);
	}

	expect_connection(server);
}
