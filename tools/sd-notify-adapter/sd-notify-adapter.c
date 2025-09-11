// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <err.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#define ARRAY_SIZE(s) (sizeof(s)/sizeof(s[0]))

enum {
	socket_fd,
	notification_fd,
};

struct iovec msg;

#define READY "READY=1"
#define READY_SIZE (sizeof(READY) - 1)

static void process_notification(void)
{
	ssize_t first_recv_size = recv(socket_fd, msg.iov_base, msg.iov_len,
	                               MSG_TRUNC | MSG_PEEK);
	if (first_recv_size == -1) {
		if (errno == EINTR)
			return; // signal caught
		err(EXIT_FAILURE, "recv from notification socket");
	}
	size_t size = (size_t)first_recv_size;
	if (size == 0)
		return; // avoid arithmetic on NULL pointer
	if (size > msg.iov_len) {
		msg.iov_base = realloc(msg.iov_base, size);
		if (msg.iov_base == NULL)
			err(EXIT_FAILURE, "allocation failure");
		msg.iov_len = size;
	}
	ssize_t second_recv_size = recv(socket_fd, msg.iov_base, msg.iov_len,
	                                MSG_CMSG_CLOEXEC | MSG_TRUNC);
	if (second_recv_size == -1) {
		if (errno == EINTR)
			return;
		err(EXIT_FAILURE, "recv from notification socket");
	}
	assert(first_recv_size == second_recv_size);
	for (char *next, *cursor = msg.iov_base, *end = cursor + size;
	     cursor != NULL; cursor = (next == NULL ? NULL : next + 1)) {
		next = memchr(cursor, '\n', (size_t)(end - cursor));
		size_t message_size = (size_t)((next == NULL ? end : next) - cursor);
		if (message_size == READY_SIZE &&
		    memcmp(cursor, READY, READY_SIZE) == 0) {
			ssize_t write_size = write(notification_fd, "\n", 1);
			if (write_size != 1)
				err(EXIT_FAILURE, "writing to notification descriptor");
			exit(0);
		}
	}
}

int main(int argc, char **)
{
	if (argc != 1)
		errx(EXIT_FAILURE, "stdin is listening socket, stdout is notification pipe");
	for (;;) {
		struct pollfd p[] = {
			{
				.fd = socket_fd,
				.events = POLLIN,
				.revents = 0,
			},
			{
				.fd = notification_fd,
				.events = 0,
				.revents = 0,
			},
		};
		int r = poll(p, ARRAY_SIZE(p), -1);
		if (r < 0) {
			if (errno == EINTR)
				continue;
			err(EXIT_FAILURE, "poll");
		}
		if (p[0].revents) {
			if (p[0].revents & POLLERR)
				errx(EXIT_FAILURE, "unexpected POLLERR");
			if (p[0].revents & POLLIN)
				process_notification();
		}
		if (p[1].revents)
			errx(EXIT_FAILURE, "s6 closed its pipe before the child was ready");
	}
}
