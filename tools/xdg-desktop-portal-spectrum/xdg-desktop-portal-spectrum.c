// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2024 Alyssa Ross <hi@alyssa.is>

#include <arpa/inet.h>
#include <err.h>
#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <sys/socket.h>
#include <sys/stat.h>

#include <linux/vm_sockets.h>

#include <dbus/dbus.h>

#include "config.h"

static const uint32_t HOST_PORT = 219;

static int parse_u32(const char *s, uint32_t *v)
{
	char *end;

	errno = EINVAL;
	if (!s || s[0] < '0' || s[0] > '9')
		return -1;

	errno = 0;
	*v = strtol(s, &end, 10);
	if (errno)
		return -1;
	if (*end) {
		errno = EINVAL;
		return -1;
	}

	return 0;
}

static int write_all(int fd, const void *buf, size_t len)
{
	int r;

	do {
		r = write(fd, buf, len);
		if (r == -1)
			return -1;
		buf = (char *)buf + r;
		len -= r;
	} while (len);

	return 0;
}

static int connect_to_host(void)
{
	struct sockaddr_vm addr = {
		.svm_family = AF_VSOCK,
		.svm_cid = VMADDR_CID_HOST,
		.svm_port = HOST_PORT,
	};
	char handshake[] = { 1, 1 };
	char version;
	int sock = socket(AF_VSOCK, SOCK_STREAM, 0);

	if (sock == -1)
		err(EXIT_FAILURE, "creating vsock socket");

	if (connect(sock, (struct sockaddr *)&addr, sizeof addr) == -1)
		err(EXIT_FAILURE, "connecting to cid %" PRIu32 " port %" PRIu32,
		    addr.svm_cid, addr.svm_port);

	if (write_all(sock, handshake, sizeof handshake) == -1)
		err(EXIT_FAILURE, "writing handshake to vsock socket");

	if (read(sock, &version, 1) == -1)
		err(EXIT_FAILURE, "reading handshake version");
	if (version != 1)
		err(EXIT_FAILURE, "unexpected protocol version %d", version);

	return sock;
}

constexpr size_t HOST_FS_ROOT_DIR_LEN = sizeof HOST_FS_ROOT_DIR - 1;
static_assert(HOST_FS_ROOT_DIR_LEN < UINT32_MAX);

static void send_info(int sock, uint32_t port)
{
	uint32_t fs_root_dir_len_u32_be = htonl(HOST_FS_ROOT_DIR_LEN);
	port = htonl(port);

	if (write_all(sock, &port, sizeof port) == -1)
		err(EXIT_FAILURE, "writing port to vsock socket");
	if (write_all(sock, &fs_root_dir_len_u32_be, 4) == -1)
		err(EXIT_FAILURE, "writing fs root length to vsock socket");
	if (write_all(sock, HOST_FS_ROOT_DIR, HOST_FS_ROOT_DIR_LEN) == -1)
		err(EXIT_FAILURE, "writing fs root to vsock socket");
}

static void check_result(int sock)
{
	char r;
	if (read(sock, &r, 1) == -1)
		err(EXIT_FAILURE, "reading result");
	if (r)
		errx(EXIT_FAILURE, "host sent bad result: %hhd", r);
}

int main(void)
{
	char *addr = getenv("DBUS_STARTER_ADDRESS");

	DBusAddressEntry **entries;
	int entries_len, i, sock;
	DBusError error;

	const char *port_str;
	uint32_t port;

	if (!addr)
		errx(EXIT_FAILURE, "DBUS_STARTER_ADDRESS not set");

	if (!dbus_parse_address(addr, &entries, &entries_len, &error))
		errx(EXIT_FAILURE, "parsing D-Bus address '%s': %s",
		     addr, error.message);

	for (i = 0; i < entries_len; i++) {
		if (strcmp(dbus_address_entry_get_method(entries[i]), "vsock"))
			continue;

		if (!(port_str = dbus_address_entry_get_value(entries[i], "port")))
			errx(EXIT_FAILURE, "missing vsock port in D-Bus address '%s'",
			     addr);

		if (parse_u32(port_str, &port) == -1)
			err(EXIT_FAILURE, "D-Bus address vsock port");

		sock = connect_to_host();
		send_info(sock, port);
		check_result(sock);
		return 0;
	}
}
