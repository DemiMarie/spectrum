// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

#include "lib.h"

#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <sys/poll.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/utsname.h>

struct vm {
	pthread_t console_thread;
	FILE *console[2];
	int prompt_event[2];
};

static void chld_handler(int)
{
	exit(EXIT_FAILURE);
}

static void exit_on_sigchld(void)
{
	struct sigaction sa = {
		.sa_handler = chld_handler,
		.sa_flags = SA_NOCLDSTOP,
	};
	if (!sigaction(SIGCHLD, &sa, nullptr))
		return;

	perror("sigaction");
	exit(EXIT_FAILURE);
}

static char *make_tmp_dir(void)
{
	char *dir, *run;
	if (!(run = secure_getenv("XDG_RUNTIME_DIR"))) {
		fputs("warning: XDG_RUNTIME_DIR unset\n", stderr);
		run = "/tmp";
	}
	if (asprintf(&dir, "%s/spectrum-test.XXXXXX", run) == -1) {
		perror("asprintf");
		exit(EXIT_FAILURE);
	}
	if (!mkdtemp(dir)) {
		perror("mkdtemp");
		exit(EXIT_FAILURE);
	}
	return dir;
}

static int setup_unix(const char *path)
{
	int r, fd;
	struct sockaddr_un addr = { .sun_family = AF_UNIX };

	r = snprintf(addr.sun_path, sizeof addr.sun_path, "%s", path);
	if (r >= sizeof addr.sun_path) {
		fputs("XDG_RUNTIME_DIR too long\n", stderr);
		exit(EXIT_FAILURE);
	}

	if (r < 0) {
		fputs("snprintf error\n", stderr);
		exit(EXIT_FAILURE);
	}

	if ((fd = socket(AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0)) == -1) {
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

struct console_thread_args {
	FILE *console;
	int prompt_event;
};

static void *console_thread(void *arg)
{
	struct console_thread_args *args = (struct console_thread_args *)arg;

	char *needle = "~ # ";
	size_t i = 0;
	int c;

	while ((c = getc_unlocked(args->console)) != EOF) {
		fputc(c, stderr);
		i = c == needle[i] ? i + 1 : 0;

		if (!needle[i]) {
			i = 0;
			if (write(args->prompt_event, "\n", 1) == -1 && errno != EAGAIN) {
				perror("write");
				exit(EXIT_FAILURE);
			}
		}
	}

	fputs("unexpected EOF from console\n", stderr);
	exit(EXIT_FAILURE);
}

static void start_console_thread(struct vm *vm, pthread_t *thread)
{
	int e;
	struct console_thread_args *args = malloc(sizeof(*args));

	if (!args) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}

	args->console = vm->console[0];
	args->prompt_event = vm->prompt_event[1];

	if ((e = pthread_create(thread, nullptr, console_thread, args))) {
		fprintf(stderr, "pthread_create: %s\n", strerror(e));
		exit(EXIT_FAILURE);
	}
}

void wait_for_prompt(struct vm *vm)
{
	char c;
	struct pollfd pollfd = { .fd = vm->prompt_event[0], .events = POLLIN };
	if (poll(&pollfd, 1, -1) == -1) {
		perror("poll");
		exit(EXIT_FAILURE);
	}
	if (pollfd.revents != POLLIN) {
		fprintf(stderr, "unexpected poll events from prompt event: %hx\n", pollfd.revents);
		exit(EXIT_FAILURE);
	}
	while (read(vm->prompt_event[0], &c, 1) != -1);
	if (errno != EAGAIN && errno != EINTR) {
		perror("read prompt event");
		exit(EXIT_FAILURE);
	}
}

FILE *vm_console_writer(struct vm *vm)
{
	return vm->console[1];
}

struct vm *start_qemu(struct config c)
{
	struct utsname u;
	int console_listener, console_conn;
	char *arch, *args[] = {
		(char *)c.run_qemu,
		"-drive", nullptr,
		"-drive", nullptr,
		"-drive", nullptr,
		"-smbios", nullptr,
		"-m", "4G",
		"-nodefaults",
		"-machine", "virtualization=on",
		"-cpu", "max",
		"-device", "qemu-xhci",
		"-device", "virtio-keyboard",
		"-device", "virtio-mouse",
		"-device", "virtio-gpu",
		"-netdev", "user,id=net0",
		"-device", "e1000e,netdev=net0",
		"-monitor", "vc",
		"-vga", "none",
		"-chardev", "socket,id=socket,path=console",
		c.serial.optname ? (char *)c.serial.optname : "-serial",
		c.serial.optval ? (char *)c.serial.optval : "chardev:socket",
		nullptr,
	};
	char **efi_arg = &args[2], **img_arg = &args[4],
	     **user_data_arg = &args[6], **console_arg = &args[8];
	struct vm *r = malloc(sizeof *r);

	if (!r) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}

	if (!(arch = getenv("ARCH"))) {
		uname(&u);
		arch = u.machine;
	}
	if (!c.serial.console && !strcmp(arch, "x86_64"))
		c.serial.console = "ttyS0";

	console_listener = setup_unix("console");

	switch (fork()) {
	case -1:
		perror("fork");
		exit(EXIT_FAILURE);
	case 0:
		if (prctl(PR_SET_PDEATHSIG, SIGTERM) == -1) {
			perror("prctl");
			exit(EXIT_FAILURE);
		}

		if (asprintf(efi_arg, "file=%s,format=raw,if=pflash,readonly=true", c.drives.efi) == -1 ||
		    asprintf(img_arg, "file=%s,format=raw,if=virtio,readonly=true", c.drives.img) == -1 ||
		    asprintf(user_data_arg, "file=%s,format=raw,if=virtio,readonly=true", c.drives.user_data) == -1 ||
		    asprintf(console_arg, "type=11,value=io.systemd.stub.kernel-cmdline-extra=%s%s",
		             c.serial.console ? "console=" : "",
		             c.serial.console ? c.serial.console : "") == -1) {
			perror("asprintf");
			exit(EXIT_FAILURE);
		}

		execv(c.run_qemu, args);
		perror("execv");
		exit(EXIT_FAILURE);
	}

	if ((console_conn = accept4(console_listener, nullptr, nullptr, SOCK_CLOEXEC)) == -1) {
		perror("accept");
		exit(EXIT_FAILURE);
	}

	if (!(r->console[0] = fdopen(console_conn, "r"))) {
		perror("fdopen");
		exit(EXIT_FAILURE);
	}

	if ((console_conn = fcntl(console_conn, F_DUPFD_CLOEXEC, 0)) == -1) {
		perror("fcntl(F_DUPFD_CLOEXEC)");
		exit(EXIT_FAILURE);
	}

	if (!(r->console[1] = fdopen(console_conn, "a"))) {
		perror("fdopen");
		exit(EXIT_FAILURE);
	}

	errno = 0;
	if (setvbuf(r->console[1], nullptr, _IOLBF, 0)) {
		if (errno)
			perror("setvbuf");
		else
			fputs("setvbuf failed\n", stderr);
		exit(EXIT_FAILURE);
	}

	if (pipe2(r->prompt_event, O_CLOEXEC|O_NONBLOCK) == -1) {
		perror("pipe");
		exit(EXIT_FAILURE);
	}

	start_console_thread(r, &r->console_thread);
	wait_for_prompt(r);
	return r;
}

static char *getenv_or_die(const char *name)
{
	char *r = getenv(name);
	if (!r) {
		fprintf(stderr, "%s not set\n", name);
		exit(EXIT_FAILURE);
	}
	return r;
}

int main(int argc, char *argv[])
{
	exit_on_sigchld();

	if (argc != 2) {
		fputs("Usage: test run_qemu\n", stderr);
		exit(EXIT_FAILURE);
	}

	struct config c = {
		.run_qemu = argv[1],
		.drives = {
			.efi = getenv_or_die("EFI_PATH"),
			.img = getenv_or_die("IMG_PATH"),
			.user_data = getenv_or_die("USER_DATA_PATH"),
		},
	};

	if (strchr(c.drives.efi, ',') || strchr(c.drives.img, ',') ||
	    strchr(c.drives.user_data, ',')) {
		fputs("arguments contain commas\n", stderr);
		exit(EXIT_FAILURE);
	}

	if (unshare(CLONE_NEWUSER|CLONE_NEWNET) == -1) {
		perror("unshare");
		exit(EXIT_FAILURE);
	}

	if (chdir(make_tmp_dir()) == -1) {
		perror("chdir");
		exit(EXIT_FAILURE);
	}

	test(c);
}
