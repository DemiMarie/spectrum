// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
// check_posix and check_posix_bool are based on code with following license:
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
#include <getopt.h>
#include <sys/epoll.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/signalfd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <sys/wait.h>
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
	__builtin_unreachable();
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

// Parse a decimal int.  Returns INT_MIN (assumed invalid) on failure.
static int parse_int(const char *arg) {
	char *end = (char *)arg;
	if (*arg == '0') {
		return arg[1] == '\0' ? 0 : INT_MIN;
	}
	bool negative = *arg == '-';
	if (arg[negative] < '1' || arg[negative] > '9') {
		return INT_MIN;
	}
	errno = 0;
	long v = strtol(arg, &end, 10);
	if (v < INT_MIN || v > INT_MAX || errno || *end != '\0') {
		return INT_MIN;
	}
	return (int)v;
}

[[noreturn]]
static void flush_and_exit(int status) {
	fflush(NULL);
	if ((ferror(stdout) || ferror(stderr)) && status == 0)
		status = EX_IOERR;
	exit(status);
}

#if O_RDONLY > 3 || O_WRONLY > 3 || O_RDWR > 3
# error unsupported O_* constants
#endif

static void check_fd_usable(int fd, bool writable) {
	int raw_flags = fcntl(fd, F_GETFL);
	if (raw_flags == -1) {
		err(errno == EBADF ? EX_USAGE : EX_OSERR, "fcntl(%d, F_GETFD)", fd);
	}
	int flags = raw_flags & 3;
	if (flags != O_RDWR && flags != (writable ? O_WRONLY : O_RDONLY)) {
		errx(EX_USAGE, "File descriptor %d is not %s (flags 0x%x)", fd, writable ? "writable" : "readable", raw_flags);
	}
}

static int compare_ints(const void *fst, const void *snd) {
	int first = *(const int *)fst;
	int second = *(const int *)snd;
	return first < second ? -1 : (first > second ? 1 : 0);
}

// Close file descriptors that are not on the provided list
// and are not stdin, stdout, or stderr.  fds argument is
// sorted in-place.
static void close_unwanted_fds(int *fds, size_t count)
{
	int last_to_keep = 2;
	qsort(fds, count, sizeof(fds[0]), compare_ints);
	for (size_t i = 0; i < count; ++i) {
		if (fds[i] <= 2) {
			// Never close stdin, stdout, stderr, or a negative FD.
			assert(fds[i] >= -1);
			continue;
		}
		if (fds[i] - last_to_keep > 1) {
			// 'man 2 close_range' guarantees that no errors can occur.
			if (syscall(SYS_close_range, (long)last_to_keep + 1L, (long)fds[i] - 1L, 0L)) {
				assert(!"close_range failed");
			}
		}
		last_to_keep = fds[i];
	}
	// 'man 2 close_range' guarantees that no errors can occur.
	if (syscall(SYS_close_range, (long)((unsigned)last_to_keep + 1U), (long)~0U, 0L)) {
		assert(!"close_range failed");
	}
}

// Begin non-reusable code
static void handler(struct signalfd_siginfo *info, int child_pid) {
	if (info->ssi_signo != SIGCHLD) {
		kill(child_pid, info->ssi_signo);
		return;
	}
	siginfo_t child_info;
	do {
		if (waitid(P_ALL, 0, &child_info, WEXITED | WNOHANG)) {
			abort(); // Cannot happen
		}
		if (child_info.si_pid == 0) {
			return;
		}
	} while (child_info.si_pid != child_pid);
	switch (child_info.si_code) {
	case CLD_EXITED:
		flush_and_exit(child_info.si_status);
	case CLD_DUMPED: {
		// Avoid creating a pointless core file
		struct rlimit zero = {};
		setrlimit(RLIMIT_CORE, &zero);
		[[fallthrough]];
	}
	case CLD_KILLED:
		for (;;) {
			sigset_t list;
			check_posix_bool(sigemptyset(&list), "sigfillset");
			check_posix_bool(sigaddset(&list, child_info.si_code), "sigaddset");
			check_posix_bool(sigprocmask(SIG_UNBLOCK, &list, NULL), "sigprocmask");
			struct sigaction act = {};
			act.sa_handler = SIG_DFL;
			check_posix_bool(sigaction(child_info.si_code, &act, NULL),
					"sigaction(%d)", (int)child_info.si_code);
			raise(child_info.si_code);
		}
	default:
		abort(); // Not reached
	}
}

static bool ready;
static bool reloading;
static int notification_fd = -1;

static int bind_notification_socket(const char *socket_path) {
	union {
		struct sockaddr_un un;
		struct sockaddr addr;
	} a = {};
	if (socket_path[0] != '/') {
		errx(EX_USAGE, "Path %s is not absolute", socket_path);
	}
	size_t len = strlen(socket_path);
	// >= for NUL terminator
	if (len >= sizeof(a.un.sun_path)) {
		errx(EX_USAGE, "Path %s is too long", socket_path);
	}
	memcpy(a.un.sun_path, socket_path, len + 1);
	a.un.sun_family = AF_UNIX;
	int fd = check_posix(socket(AF_UNIX, SOCK_DGRAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0), "socket");

	// The PID of the child is used for authentication.
	int status = 1;
	check_posix_bool(setsockopt(fd, SOL_SOCKET, SO_PASSCRED, &status, (socklen_t)sizeof(status)),
			"setsockopt(SO_PASSCRED)");

	// There is no way to set the mode explicitly so one must save and restore the umask.
	mode_t old_mask = umask(0077);
	for (;;) {
		do {
			status = bind(fd, &a.addr, (socklen_t)(len + 1 + offsetof(struct sockaddr_un, sun_path)));
		} while (status == -1 && errno == EINTR);
		if (!(status == -1 && errno == EADDRINUSE)) {
			check_posix_bool(status, "bind(%s)", socket_path);
			break;
		}

		// If the socket is already in use, unlink it so that it can be bound to.
		check_posix_bool(unlink(socket_path), "unlink(%s)", socket_path);
	}
	umask(old_mask);

	// Set NOTIFY_SOCKET so that the child knows where to send the message.
	check_posix_bool(setenv("NOTIFY_SOCKET", a.un.sun_path, 1), "setenv");
	return fd;
}

static void process_notification(int fd, struct msghdr *const msg, const char *const initial_buffer, int child_pid) {
	pid_t sender_pid = -1;
	ssize_t data = recvmsg(fd, msg, MSG_CMSG_CLOEXEC | MSG_DONTWAIT | MSG_TRUNC | MSG_PEEK);
	if (data == -1) {
		if (errno == EINTR) {
			return; // signal caught
		}
		if (errno == EAGAIN || errno == EWOULDBLOCK) {
			return; // spurious wakeup
		}
	}
	size_t size = (size_t)check_posix(data, "recvmsg");
	if (size > (size_t)INT_MAX) {
		// cannot happen on Linux, don't bother implementing
		size = (size_t)INT_MAX;
	}
	assert(msg->msg_iovlen == 1);
	struct iovec *v = msg->msg_iov;
	if (msg->msg_flags & MSG_TRUNC) {
		char *b = (v[0].iov_base == initial_buffer) ? malloc(size) : realloc(v[0].iov_base, size);
		if (b != NULL) {
			v[0].iov_base = b;
			v[0].iov_len = size;
		}
	}
	size = (size_t)check_posix(recvmsg(fd, msg, MSG_CMSG_CLOEXEC | MSG_DONTWAIT | MSG_TRUNC), "recvmsg");
	for (struct cmsghdr *cmsg = CMSG_FIRSTHDR(msg); cmsg; cmsg = CMSG_NXTHDR(msg, cmsg)) {
		size_t data_len = cmsg->cmsg_len - sizeof(struct cmsghdr);
		if (cmsg->cmsg_level != SOL_SOCKET) {
			continue;
		}
		if (cmsg->cmsg_type == SCM_RIGHTS) {
			int received_fd;
			for (size_t i = 0; data_len - i >= sizeof(received_fd); i += sizeof(received_fd)) {
				memcpy(&received_fd, CMSG_DATA(cmsg) + i, sizeof(received_fd));
				(void)close(received_fd);
			}
		}
		if (cmsg->cmsg_type == SCM_CREDENTIALS) {
			struct ucred creds;
			assert(data_len >= sizeof(creds));
			assert(sender_pid == -1);
			memcpy(&creds, CMSG_DATA(cmsg), sizeof(creds));
			sender_pid = creds.pid;
		}
	}
	if (sender_pid != child_pid) {
		warnx("Process %jd cannot notify\n", (intmax_t)sender_pid);
		return;
	}
	const char *cursor = v[0].iov_base;
	const char *const end = cursor + size;
	for (char *next; cursor != NULL; cursor = (next == NULL ? NULL : next + 1)) {
		next = memchr(cursor, '\n', (size_t)(end - cursor));
		size_t message_size = (size_t)((next == NULL ? end : next) - cursor);

		// TODO: avoid repeating sizeof(string)
		if (memchr(cursor, '\0', message_size) != NULL) {
			warnx("Child sent NUL byte");
		} else {
			warnx("Notification from child: %.*s", (int)message_size, cursor);
			if (message_size == sizeof("READY=1") - 1 && memcmp(cursor, "READY=1", sizeof("READY=1") - 1) == 0) {
				if (!ready) {
					warnx("Child notified readiness");
					if (notification_fd != -1 &&
					    check_posix(write(notification_fd, "Ready\n", sizeof("Ready")), "write") != sizeof("Ready")) {
						errx(EX_OSERR, "cannot notify parent of readiness");
					}
				}
				ready = true;
				if (reloading) {
					warnx("Child configuration reload complete");
				} else {
					warnx("Child ready");
				}
				reloading = false;
			} else if (message_size == sizeof("RELOADING=1") - 1 && memcmp(cursor, "RELOADING=1", sizeof("RELOADING=1") - 1) == 0) {
				warnx("Child is reloading its configuration");
				reloading = true;
			} else if (message_size >= sizeof("STATUS") && memcmp(cursor, "STATUS=", sizeof("STATUS")) == 0) {
				warnx("Child status: %.*s", (int)(message_size - sizeof("STATUS")), cursor + sizeof("STATUS"));
			} else {
				// Unknown status or extra newlines, ignore
			}
		}
	}
}

enum {
	S6_NOTIFY_FD = 256,
	SYSTEMD_NOTIFY_SOCKET,
	LOCK_FD,
};

static const struct option longopts[] = {
	{ "oom-score-adj", required_argument, NULL, 'o' },
	{ "die-with-parent", required_argument, NULL, 'd' },
	{ "help", no_argument, NULL, 'h' },
	{ "s6-notify-fd", required_argument, NULL, S6_NOTIFY_FD },
	{ "notify-socket", required_argument, NULL, SYSTEMD_NOTIFY_SOCKET },
	{ "lock-fd", required_argument, NULL, LOCK_FD },
	{ "arg0", required_argument, NULL, '0' },
	{ NULL, 0, NULL, 0 },
};

[[noreturn]]
static void usage(int arg) {
	fputs("Usage: notification-fd OPTIONS -- program arguments...\n"
	      "\n"
	      "  -h, --help                              Print this message\n"
	      "      --s6-notify-fd                      File descriptor for S6-style notification\n"
	      // This avoids confusion with positional parameters (program and arguments)
	      // and allows providing a default in the future (such as /run/sd-notify-adapter/PID).
	      "      --notify-socket                     Socket to listen for notifications on (mandatory)\n"
	      "      --lock-fd lock_fd                   Keep lock_fd open\n"
	      "      --arg0=ARG0                         Set the argv[0] passed to the child process\n"
	      "      --oom-score-adj=ADJUSTMENT          Adjust the OOM score of the process and its children.\n"
	      "      --die-with-parent=SIGNAL            Kill both this process and its child with SIGNAL if\n"
	      "                                          the parent process dies\n",
	      arg ? stderr : stdout);
	flush_and_exit(arg);
}

enum {
	NOTIFY_FD,
	SIGNAL_FD,
	PARENT_PIPE_FD,
};

int main(int argc, char **argv) {
	// Avoid out-of-bounds read getting argv[1].
	if (argc < 1) {
		errx(EX_USAGE, "argc == 0");
	}
	for (int i = 0; i < 3; ++i) {
		check_fd_usable(i, i != 0);
	}
	char *arg0 = NULL;
	const char *lastopt;
	const char *socket_path = NULL;
	int lock_fd = -1;
	int oom_score_adj = INT_MIN;
	int exit_signal = 0;
	for (;;) {
		int longindex = -1;
		lastopt = argv[optind];
		int res = getopt_long(argc, argv, "+h", longopts, &longindex);
		if (res == -1) {
			break;
		}
		if (res == '?') {
			usage(EX_USAGE);
		}
		// getopt_long accepts abbreviated options. Disable this misfeature.
		if (lastopt[0] == '-' && lastopt[1] == '-') {
			const char *optname = lastopt + 2;
			assert(longindex >= 0 && longindex < (int)(sizeof(longopts)/sizeof(longopts[0])));
			const char *expected = longopts[longindex].name;
			if (strncmp(expected, optname, strlen(expected)) != 0) {
				char *equal = strchr(optname, '=');
				errx(EX_USAGE,
				     "Option --%.*s must be written as --%s",
				     equal ? (int)(equal - optname) : INT_MAX,
				     optname, expected);
			}
		}
		switch (res) {
		case 'o':
			oom_score_adj = parse_int(optarg);
			if (oom_score_adj < -1000 || oom_score_adj > 1000) {
				errx(EX_USAGE, "Invalid OOM score adjustment %s", optarg);
			}
			break;
		case 'h':
			usage(0);
		case S6_NOTIFY_FD:
			if (notification_fd != -1) {
				errx(EX_USAGE, "--s6-notify-fd passed twice");
			}
			notification_fd = parse_int(optarg);
			if (notification_fd < 3) {
				errx(EX_USAGE, "Invalid notification descriptor '%s'", optarg);
			}
			// Don't leak this into the child.
			check_posix_bool(ioctl(notification_fd, FIOCLEX),
			                 "Bad FD argument to --s6-notify-fd: %d",
			                 notification_fd);
			check_fd_usable(notification_fd, true);
			break;
		case SYSTEMD_NOTIFY_SOCKET:
			if (socket_path != NULL) {
				errx(EX_USAGE, "--notify-socket passed twice");
			}
			socket_path = optarg;
			break;
		case LOCK_FD:
			if (lock_fd != -1) {
				errx(EX_USAGE, "--lock-fd must not be given more than once\n");
			}
			lock_fd = parse_int(optarg);
			if (lock_fd < 3) {
				errx(EX_USAGE, "Invalid lock file descriptor %s\n", optarg);
			}
			break;
		case '0':
			if (arg0 != NULL) {
				errx(EX_USAGE, "--arg0 must not be given multiple times");
			}
			arg0 = optarg;
			break;
		case 'd':
			if (exit_signal) {
				errx(EX_USAGE, "Parent death signal cannot be given more than once");
			}
			exit_signal = parse_int(optarg);
			if ((exit_signal < 1 || exit_signal > 31) &&
			    (exit_signal < SIGRTMIN && exit_signal > SIGRTMAX)) {
				errx(EX_USAGE, "invalid signal specification '%s'", optarg);
			}
			check_posix_bool(prctl(PR_SET_PDEATHSIG, exit_signal), "prctl(PR_SET_PDEATHSIG)");
			break;
		default:
			assert(0); // not reached
		}
	}

	if (argc <= optind) {
		usage(EX_USAGE);
	}
	if (strcmp(lastopt, "--") != 0) {
		errx(EX_USAGE, "no -- before non-option arguments");
	}
	if (socket_path == NULL) {
		errx(EX_USAGE, "--notify-socket not passed");
	}

	char **const args_to_exec = argv + optind;

	// Command line fully parsed.

	// Ignore SIGPIPE.
	struct sigaction act = { };
	act.sa_handler = SIG_IGN;
	check_posix_bool(sigaction(SIGPIPE, &act, NULL), "sigaction(SIGPIPE)");

	// Open file descriptors.
	int epoll_fd = check_posix(epoll_create1(EPOLL_CLOEXEC), "epoll_create1");
	int notify_socket_fd = bind_notification_socket(socket_path);
	struct epoll_event event = { .events = EPOLLIN, .data.u64 = NOTIFY_FD };
	check_posix_bool(epoll_ctl(epoll_fd, EPOLL_CTL_ADD, notify_socket_fd, &event), "epoll_ctl");

	// Receive notifications for all catchable signals.
	sigset_t new_mask;
	sigfillset(&new_mask);
	int signal_fd = check_posix(signalfd(-1, &new_mask, SFD_NONBLOCK | SFD_CLOEXEC), "signalfd");
	event.data.u64 = SIGNAL_FD;
	check_posix_bool(epoll_ctl(epoll_fd, EPOLL_CTL_ADD, signal_fd, &event), "epoll_ctl");
	event = (struct epoll_event) { .events = 0, .data.u64 = PARENT_PIPE_FD };
	int r = epoll_ctl(epoll_fd, EPOLL_CTL_ADD, notification_fd, &event);
	if (r != 0) {
		assert(r == -1);
		if (errno != EPERM) {
			err(EX_OSERR, "epoll_ctl");
		}
	}
	int dev_null = check_posix(open("/dev/null", O_RDWR | O_CLOEXEC | O_NOCTTY, 0666), "open(/dev/null)");

	/* Adjust OOM score if desired */
	if (oom_score_adj != INT_MIN) {
		char *p;
		int fd = check_posix(open("/proc/self/oom_score_adj",
		                          O_WRONLY | O_CLOEXEC | O_NOCTTY | O_NOFOLLOW),
		                     "open(\"/proc/self/oom_score_adj\")");
		int to_write = check_posix(asprintf(&p, "%d\n", oom_score_adj), "asprintf");
		ssize_t written = check_posix(write(fd, p, (size_t)to_write), "write(\"/proc/self/oom_score_adj\")");
		assert(written == to_write);
		free(p);
	}

	// To work around a kernel race condition [1], the child process needs
	// to handshake with its parent after calling prctl(PR_SET_PDEATHSIG).
	// However, this is not necessary if the parent is PID 1 in its PID
	// namespace, as if it exits all of its children die with SIGKILL.
	//
	// It is not necessary to close these file descriptors.  The kernel
	// will close them when the child calls execve().  Since the FDs
	// are not in the list passed to close_unwanted_fds(), they will
	// be closed by close_range().
	//
	// [1]: https://lore.kernel.org/lkml/20250913-fix-prctl-pdeathsig-race-v1-1-44e2eb426fe9@gmail.com
	int race_prevention_fds[2] = { -1, -1 };
	if (exit_signal != 0 && getpid() != 1) {
		check_posix_bool(socketpair(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0,
		                            race_prevention_fds),
		                 "socketpair");
	}

	// Fork
	pid_t child_pid = check_posix(fork(), "fork");
	if (child_pid == 0) {
		const char *progname = arg0 != NULL ? arg0 : args_to_exec[0];
		if (notification_fd != -1) {
			close(notification_fd);
		}
		if (arg0 != NULL) {
			args_to_exec[0] = arg0;
		}
		close(notification_fd);
		if (race_prevention_fds[1] != -1) {
			ssize_t write_result;
			char buf[] = { 0 };
			check_posix_bool(prctl(PR_SET_PDEATHSIG, exit_signal), "prctl(PR_SET_PDEATHSIG)");
			do {
				write_result = write(race_prevention_fds[1], buf, sizeof(buf));
			} while (write_result == -1 && errno == EINTR);
			if (write_result != 1) {
				err(126, "write to parent");
			}
			assert(write_result == 1);
			do {
				write_result = read(race_prevention_fds[1], buf, sizeof(buf));
			} while (write_result == -1 && errno == EINTR);
			if (write_result == 0) {
				errx(126, "Parent process died unexpectedly");
			}
			if (write_result != 1) {
				err(126, "read from parent");
			}
			assert(buf[0] == 1);
		}
		execvp(progname, args_to_exec);
		err(errno == ENOENT ? 127 : 126, "execve: %s", progname);
	}

	// Block all catchable signals so the event loop can handle them.
	// This must not be done before forking, as otherwise the child
	// process temporarily has signals blocked but no way of handling
	// them.  Note that signals due to a CPU exception cannot be
	// blocked and will have their normal effect.  (They can be caught,
	// but this code doesn't catch them.)
	if (sigprocmask(SIG_BLOCK, &new_mask, NULL)) {
		abort(); // cannot happen per manpage
	}

	// Main event loop.
	if (race_prevention_fds[0] != -1) {
		ssize_t read_result;
		char buf[] = { 1 };
		do {
			read_result = read(race_prevention_fds[0], buf, sizeof(buf));
		} while (read_result == -1 && errno == EINTR);
		if (read_result == 0) {
			errx(126, "Child process died unexpectedly");
		}
		if (read_result != 1) {
			err(126, "read from child");
		}
		assert(buf[0] == 0);
		buf[0] = 1;
		do {
			read_result = write(race_prevention_fds[0], buf, sizeof(buf));
		} while (read_result == -1 && errno == EINTR);
		if (read_result != 1) {
			err(126, "write to child");
		}
	}

	dup2(dev_null, 0);
	dup2(dev_null, 1);

	// Close extra file descriptors in the parent, to avoid keeping an extra reference
	// to the file description.  Otherwise the child closing the write end of a pipe
	// would not cause another process to get EOF.  This also closes the FD to /dev/null
	// and the race prevention FDs.
	{
		int fds_to_sort[] = { notification_fd, epoll_fd, signal_fd, notify_socket_fd, lock_fd };
		close_unwanted_fds(fds_to_sort, ARRAY_SIZE(fds_to_sort));
	}

	// Main event loop
	union {
		struct cmsghdr hdr;
		char buf[CMSG_SPACE(sizeof(struct ucred)) + CMSG_SPACE(sizeof(int) * 253)];
	} cmsg_buffer;
	char buf[sizeof("RELOADING=1\n") - 1];
	struct iovec v[1] = {
		{
			.iov_base = buf,
			.iov_len = sizeof(buf),
		},
	};
	struct msghdr msg = {
		.msg_name = NULL,
		.msg_namelen = 0,
		.msg_iov = v,
		.msg_iovlen = sizeof(v)/sizeof(v[0]),
		.msg_control = cmsg_buffer.buf,
		.msg_controllen = sizeof(cmsg_buffer.buf),
		.msg_flags = 0,
	};
	for (;;) {
		struct signalfd_siginfo info;
		struct epoll_event out_event[2] = {};
		int epoll_wait_result =
			check_posix(epoll_wait(epoll_fd, out_event, ARRAY_SIZE(out_event), -1),
		                    "epoll_wait");
		for (int i = 0; i < epoll_wait_result; ++i) {
			switch (out_event[i].data.u64) {
			case NOTIFY_FD: // socket
				process_notification(notify_socket_fd, &msg, buf, child_pid);
				break;
			case SIGNAL_FD: // signal
			{
				ssize_t bytes_read;
				do {
					bytes_read = read(signal_fd, &info, sizeof(info));
				} while (bytes_read == -1 && errno == EINTR);
				if (bytes_read == -1) {
					if (errno != EAGAIN) {
						warn("signalfd read");
					}
					break;
				}
				// No other return value makes sense.
				assert(bytes_read == (ssize_t)sizeof(info));
				handler(&info, child_pid);
				break;
			}
			case PARENT_PIPE_FD: /* pipe to s6-supervise */
			{
				if ((out_event->events & EPOLLERR) == 0) {
					break;
				}
				int bytes_unread = -1;
				warnx("Notification pipe closed");

				/*
				 * This prevents races.  There are three cases:
				 *
				 * 1. The parent died before being notified of readiness.
				 *    In this case, 'ready' will be false.
				 *
				 * 2. The parent died before after being notified of
				 *    readiness, but before reading all the bytes from its
				 *    pipe.  In this case, there will be a non-zero number
				 *    of bytes left in the pipe, which FIONREAD will detect.
				 *
				 * 3. The parent closed the pipe after reading all of the bytes.
				 *    In this case, the following happens-before relationships exist:
				 *
				 *    1. prctl(PR_SET_PDEATHSIG) happens-before
				 *       writing data to the pipe.
				 *
				 *    2. Writing data to the pipe happens-before
				 *       the parent reading data from the pipe.
				 *
				 *    3. Reading data from the pipe happens-before
				 *       the parent exiting, if it ever does exit.
				 *
				 *    Therefore, prctl(PR_SET_PDEATHSIG) happens-before the parent exiting,
				 *    and therefore the Linux kernel will see it if it tears down the
				 *    parent process.
				 */
				if (!ready) {
					warnx("s6-supervise died before being informed of readiness");
					if (exit_signal != 0) {
						exit(EX_OSERR);
					}
				} else {
					check_posix_bool(ioctl(notification_fd, FIONREAD, &bytes_unread), "ioctl(FIONREAD)");
					if (bytes_unread != 0) {
						warnx("s6-supervise died with %d bytes in notification pipe",
						      bytes_unread);
						if (exit_signal != 0) {
							exit(EX_OSERR);
						}
					}
				}

				if (epoll_ctl(epoll_fd, EPOLL_CTL_DEL, notification_fd, NULL) == 0) {
					// TODO: just exit here?  This looks like a kernel bug.
					close(notification_fd);
					notification_fd = -1;
				}
				break;
			}
			default:
				assert(0); // Not reached
			}
		}
	}
}
