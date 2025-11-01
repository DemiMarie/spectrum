// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

#include "lib.h"

#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <arpa/inet.h>
#include <net/if.h>

#include <sys/ioctl.h>

static int setup_server(void)
{
	int fd;
	struct ifreq ifr;

	struct sockaddr_in addr = {
		.sin_family = AF_INET,
		.sin_port = htons(1234),
		.sin_addr = { .s_addr = htonl(INADDR_LOOPBACK) },
	};

	sprintf(ifr.ifr_name, "lo");

	if ((fd = socket(AF_INET, SOCK_STREAM|SOCK_CLOEXEC, 0)) == -1) {
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
	int conn_fd;
	FILE *conn;
	char msg[7];
	size_t len;

	fputs("waiting for server connection\n", stderr);
	if ((conn_fd = accept(listener, nullptr, nullptr)) == -1) {
		perror("accept");
		exit(EXIT_FAILURE);
	}
	fputs("accepted connection!\n", stderr);
	if (!(conn = fdopen(conn_fd, "r"))) {
		perror("fdopen(server connection)");
		exit(EXIT_FAILURE);
	}

	len = fread(msg, 1, sizeof msg, conn);
	if (len != 6 || memcmp("hello\n", msg, 6)) {
		if (ferror(conn))
			perror("fread(server connection)");
		else
			fprintf(stderr, "unexpected connection data: %.*s",
			        (int)len, msg);
		exit(EXIT_FAILURE);
	}
	fclose(conn);
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

	if (fputs("set -euxo pipefail && "
	          "mkdir /run/mnt && "
	          "mount \"$(findfs UUID=a7834806-2f82-4faf-8ac4-4f8fd8a474ca)\" /run/mnt && "
	          "s6-rc -bu change vmm-env && "
	          "vm-import user /run/mnt/vms && "
	          "vm-start \"$(basename \"$(readlink /run/vm/by-name/user.nc)\")\" && "
	          "tail -Fc +0 /run/log/current /run/*.log &\n",
	          vm->console) == EOF) {
		fputs("error writing to console\n", stderr);
		exit(EXIT_FAILURE);
	}

	expect_connection(server);

	wait_for_prompt(vm->prompt_event);

	if (fputs("s6-svc -wR -r /run/vm/by-name/sys.netvm/service\n",
	          vm->console) == EOF) {
		fputs("error writing to console\n", stderr);
		exit(EXIT_FAILURE);
	}

	wait_for_prompt(vm->prompt_event);

	drain_connections(server);

	if (fputs("vm-start \"$(basename \"$(readlink /run/vm/by-name/sys.netvm)\")\"\n",
	          vm->console) == EOF) {
		fputs("error writing to console\n", stderr);
		exit(EXIT_FAILURE);
	}

	expect_connection(server);
}
