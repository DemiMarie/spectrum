// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

#include "lib.h"

#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/utsname.h>

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

static void wait_for_prompt(FILE *console)
{
	char *needle = "~ # ";
	size_t i = 0;
	int c;

	fputs("waiting for character\n", stderr);

	while ((c = fgetc(console)) != EOF) {
		fputc(c, stderr);
		i = c == needle[i] ? i + 1 : 0;
		if (!needle[i])
			return;
	}

	fputs("unexpected EOF from console\n", stderr);
	exit(EXIT_FAILURE);
}

FILE *start_qemu(struct config c)
{
	FILE *console;
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
		    asprintf(console_arg, "type=11,value=io.systemd.stub.kernel-cmdline-extra=%s%s", c.serial.console ? "console=" : "", c.serial.console) == -1) {
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
	if (!(console = fdopen(console_conn, "a+"))) {
		perror("fdopen");
		exit(EXIT_FAILURE);
	}

	fputs("waiting for console prompt\n", stderr);

	wait_for_prompt(console);

	return console;
}

int main(int argc, char *argv[])
{
	exit_on_sigchld();

	if (argc != 5) {
		fputs("Usage: test efi spectrum user_data\n", stderr);
		exit(EXIT_FAILURE);
	}

	struct config c = {
		.run_qemu = argv[1],
		.drives = {
			.efi = argv[2],
			.img = argv[3],
			.user_data = argv[4],
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
