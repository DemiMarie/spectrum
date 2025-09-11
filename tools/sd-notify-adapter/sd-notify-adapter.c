// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

#define _GNU_SOURCE 1
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
#include <sysexits.h>
#include <unistd.h>

#define ARRAY_SIZE(s) (sizeof(s)/sizeof(s[0]))

static bool ready;

enum {
	socket_fd,
	notification_fd,
};

#define READY "READY=1"
#define READY_SIZE (sizeof(READY) - 1)

static void
process_notification(struct iovec *const msg) {
	ssize_t data = recv(socket_fd, msg->iov_base, msg->iov_len,
	                    MSG_DONTWAIT | MSG_TRUNC | MSG_PEEK);
	if (data == -1) {
		if (errno == EINTR) {
			return; // signal caught
		}
		if (errno == EAGAIN || errno == EWOULDBLOCK) {
			return; // spurious wakeup
		}
		err(EX_OSERR, "recv from notification socket");
	}
	assert(data >= 0 && data <= INT_MAX);
	size_t size = (size_t)data;
	if (size == 0)
		return; // avoid arithmetic on NULL pointer
	if (size > msg->iov_len) {
		char *b = (size == 0 ? malloc(size) : realloc(msg->iov_base, size));
		if (b == NULL) {
			err(EX_OSERR, "allocation failure");
		}
		msg->iov_base = b;
		msg->iov_len = size;
	}
	data = recv(socket_fd, msg->iov_base, msg->iov_len,
	            MSG_CMSG_CLOEXEC | MSG_DONTWAIT | MSG_TRUNC);
	if (data < 0) {
		if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)
			return;
		err(EX_OSERR, "recv from notification socket");
	}
	for (char *next, *cursor = msg->iov_base, *end = cursor + size;
	     cursor != NULL; cursor = (next == NULL ? NULL : next + 1)) {
		next = memchr(cursor, '\n', (size_t)(end - cursor));
		size_t message_size = (size_t)((next == NULL ? end : next) - cursor);
		if (message_size == READY_SIZE &&
		    memcmp(cursor, READY, READY_SIZE) == 0) {
			data = write(notification_fd, "\n", 1);
			if (data != 1) {
				err(EX_OSERR, "writing to notification descriptor");
			}
			exit(0);
		}
	}
}

int main(int argc, char **argv [[gnu::unused]]) {
	if (argc != 1) {
		errx(EX_USAGE, "stdin is listening socket, stdout is notification pipe");
	}
	// Main event loop.
	struct iovec v = {
		.iov_base = NULL,
		.iov_len = 0,
	};
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
		int r = poll(p, 2, -1);
		if (r < 0) {
			if (errno == EINTR)
				continue;
			err(EX_OSERR, "poll");
		}
		if (p[0].revents) {
			if (p[0].revents & POLLERR)
				errx(EX_OSERR, "unexpected POLLERR");
			if (p[0].revents & POLLIN)
				process_notification(&v);
			break;
		}
		if (p[1].revents) {
			if (ready) {
				// Normal exit
				return 0;
			}
			errx(EX_PROTOCOL, "s6 closed its pipe before the child was ready");
		}
	}
}
