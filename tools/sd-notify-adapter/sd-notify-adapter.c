// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
// check_posix and check_posix_bool are based on playpen.c, which has
// the license:
//
// Copyright  2014 Daniel Micay
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
// CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
// TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
// SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

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
#include <sys/epoll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sysexits.h>
#include <unistd.h>

#define ARRAY_SIZE(s) (sizeof(s)/sizeof(s[0]))

// TODO: does this need to have credit given to Daniel Micay?
[[gnu::format(printf, 2, 3), gnu::warn_unused_result]]
static intmax_t check_posix(intmax_t arg, const char *fmt, ...) {
	if (arg >= 0)
		return arg;
	assert(arg == -1);
	va_list a;
	va_start(a, fmt);
	verr(EX_OSERR, fmt, a);
}

#define check_posix(arg, message, ...) \
	((__typeof__(arg))check_posix(arg, message, ## __VA_ARGS__))

// And same here
[[gnu::format(printf, 2, 3)]]
static void check_posix_bool(intmax_t arg, const char *fmt, ...) {
	if (arg != -1) {
		assert(arg == 0);
		return;
	}
	va_list a;
	va_start(a, fmt);
	verr(EX_OSERR, fmt, a);
	va_end(a); // Not reached
}

static bool ready;

enum {
	socket_fd,
	notification_fd,
};

static void
process_notification(struct iovec *const msg, const char *const initial_buffer) {
	ssize_t data = recv(socket_fd, msg->iov_base, msg->iov_len,
	                    MSG_DONTWAIT | MSG_TRUNC | MSG_PEEK);
	if (data == -1) {
		if (errno == EINTR) {
			return; // signal caught
		}
		if (errno == EAGAIN || errno == EWOULDBLOCK) {
			return; // spurious wakeup
		}
	}
	size_t size = (size_t)check_posix(data, "recv");
	if (size > (size_t)INT_MAX) {
		// cannot happen on Linux, don't bother implementing
		size = (size_t)INT_MAX;
	}
	if (size > msg->iov_len) {
		char *b = (msg->iov_base == initial_buffer) ?
			malloc(size) : realloc(msg->iov_base, size);
		if (b != NULL) {
			msg->iov_base = b;
			msg->iov_len = size;
		}
	}
	size = (size_t)check_posix(recv(socket_fd, msg->iov_base, msg->iov_len,
	                                MSG_CMSG_CLOEXEC | MSG_DONTWAIT | MSG_TRUNC),
	                           "recv");
	const char *cursor = msg->iov_base;
	const char *const end = cursor + size;
	for (char *next; cursor != NULL; cursor = (next == NULL ? NULL : next + 1)) {
		next = memchr(cursor, '\n', (size_t)(end - cursor));
		size_t message_size = (size_t)((next == NULL ? end : next) - cursor);

		// TODO: avoid repeating sizeof(string)
		if (message_size == sizeof("READY=1") - 1 &&
		    memcmp(cursor, "READY=1", sizeof("READY=1") - 1) == 0) {
			if (check_posix(write(notification_fd, "\n", 1), "write") != 1)
				assert(0);
			exit(0);
		}
	}
}

int main(int argc, char **argv [[gnu::unused]]) {
	if (argc != 1) {
		errx(EX_USAGE, "stdin is listening socket, stdout is notification pipe");
	}
	struct stat info;
	check_posix_bool(fstat(notification_fd, &info), "fstat");
	if (!S_ISFIFO(info.st_mode)) {
		errx(EX_USAGE, "notification descriptor is not a pipe");
	}
	int value;
	socklen_t len = sizeof(value);
	int status = getsockopt(socket_fd, SOL_SOCKET, SO_DOMAIN, &value, &len);
	if (status == -1 && errno == ENOTSOCK) {
		errx(EX_USAGE, "socket fd is not a socket");
	}
	check_posix_bool(status, "getsockopt");
	assert(len == sizeof(value));
	if (value != AF_UNIX) {
		errx(EX_USAGE, "socket fd must be AF_UNIX socket");
	}
	check_posix_bool(getsockopt(socket_fd, SOL_SOCKET, SO_TYPE, &value, &len),
	                 "getsockopt");
	assert(len == sizeof(value));
	if (value != SOCK_DGRAM) {
		errx(EX_USAGE, "socket must be datagram socket");
	}

	// Ignore SIGPIPE.
	struct sigaction act = { };
	act.sa_handler = SIG_IGN;
	check_posix_bool(sigaction(SIGPIPE, &act, NULL), "sigaction(SIGPIPE)");

	// Open file descriptors.
	int epoll_fd = check_posix(epoll_create1(EPOLL_CLOEXEC), "epoll_create1");
	if (epoll_fd < 3) {
		errx(EX_USAGE, "Invoked with file descriptor 0, 1, or 2 closed");
	}
	struct epoll_event event = { .events = EPOLLIN, .data.u64 = socket_fd };
	check_posix_bool(epoll_ctl(epoll_fd, EPOLL_CTL_ADD, socket_fd, &event),
	                 "epoll_ctl");
	event = (struct epoll_event) { .events = 0, .data.u64 = notification_fd };
	check_posix_bool(epoll_ctl(epoll_fd, EPOLL_CTL_ADD, notification_fd, &event),
	                 "epoll_ctl");

	// Main event loop.
	char buf[sizeof("READY=1\n") - 1];
	struct iovec v = {
		.iov_base = buf,
		.iov_len = sizeof(buf),
	};
	for (;;) {
		struct epoll_event out_event[2] = {};
		int epoll_wait_result =
			check_posix(epoll_wait(epoll_fd, out_event, ARRAY_SIZE(out_event), -1),
			            "epoll_wait");
		for (int i = 0; i < epoll_wait_result; ++i) {
			switch (out_event[i].data.u64) {
			case socket_fd:
				if (out_event[i].events != EPOLLIN) {
					errx(EX_PROTOCOL, "Unexpected event from epoll() on notification socket");
				}
				process_notification(&v, buf);
				break;
			case notification_fd:
				if (out_event[i].events != EPOLLERR) {
					errx(EX_SOFTWARE, "Unexpected event from epoll() on supervison pipe");
				}
				if (ready) {
					// Normal exit
					return 0;
				}
				errx(EX_PROTOCOL, "s6 closed its pipe before the child was ready");
				break;
			default:
				assert(0); // Not reached
			}
		}
	}
}
