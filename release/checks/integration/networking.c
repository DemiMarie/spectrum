// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

#include "lib.h"

#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <arpa/inet.h>
#include <net/if.h>

#include <sys/ioctl.h>

static void *drain(void *arg)
{
	int c;

	while ((c = fgetc((FILE *)arg)) != EOF)
		fputc(c, stderr);

	if (ferror((FILE *)arg))
		return (void *)(intptr_t)errno;

	return nullptr;
}

static pthread_t start_drain(FILE *console)
{
	pthread_t thread;
	int e;

	if (!(e = pthread_create(&thread, nullptr, drain, console)))
		return thread;

	fprintf(stderr, "pthread_create: %s\n", strerror(e));
	exit(EXIT_FAILURE);
}

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

void test(struct config c)
{
	int server = setup_server();

	FILE *console = start_qemu(c);

	if (fputs("set -euxo pipefail\n"
	          "mkdir /run/mnt\n"
	          "mount \"$(findfs UUID=a7834806-2f82-4faf-8ac4-4f8fd8a474ca)\" /run/mnt\n"
	          "s6-rc -bu change vmm-env\n"
	          "vm-import user /run/mnt/vms\n"
	          "vm-start user.nc\n"
	          "tail -Fc +0 /run/log/current /run/*.log\n",
	          console) == EOF) {
		fputs("error writing to console\n", stderr);
		exit(EXIT_FAILURE);
	}
	if (fflush(console) == EOF) {
		perror("fflush");
		exit(EXIT_FAILURE);
	}
	start_drain(console);

	expect_connection(server);
}
