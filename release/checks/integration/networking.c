// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <arpa/inet.h>
#include <net/if.h>

#include <sys/ioctl.h>
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

struct config {
	const char *run_qemu;

	struct {
		const char *efi, *img, *user_data;
	} drives;
};

static FILE *start_qemu(const char *tmp_dir, struct config c)
{
	FILE *console;
	struct utsname u;
	int console_listener, console_conn;
	char *arch, *args[] = {
		(char *)c.run_qemu,
		"-serial", nullptr,
		"-drive", nullptr,
		"-drive", nullptr,
		"-drive", nullptr,
		"-m", "4G",
		"-nodefaults",
		"-machine", "virtualization=on",
		"-cpu", "max",
		"-device", "virtio-keyboard",
		"-device", "virtio-mouse",
		"-device", "virtio-gpu",
		"-netdev", "user,id=net0",
		"-device", "e1000e,netdev=net0",
		"-monitor", "vc",
		"-vga", "none",
		"-smbios", "type=11,value=io.systemd.stub.kernel-cmdline-extra=console=ttyS0",
		nullptr,
	};

	if (!(arch = getenv("ARCH"))) {
		uname(&u);
		arch = u.machine;
	}
	if (strcmp(arch, "x86_64"))
		args[sizeof args / sizeof *args - 3] = nullptr;

	if (asprintf(&args[2], "unix:%s/console", tmp_dir) == -1) {
		perror("asprintf");
		exit(EXIT_FAILURE);
	}

	console_listener = setup_unix(args[2] + strlen("unix:"));

	switch (fork()) {
	case -1:
		perror("fork");
		exit(EXIT_FAILURE);
	case 0:
		if (prctl(PR_SET_PDEATHSIG, SIGTERM) == -1) {
			perror("prctl");
			exit(EXIT_FAILURE);
		}

		if (asprintf(&args[4], "file=%s,format=raw,if=pflash,readonly=true", c.drives.efi) == -1 ||
		    asprintf(&args[6], "file=%s,format=raw,if=virtio,readonly=true", c.drives.img) == -1 ||
		    asprintf(&args[8], "file=%s,format=raw,if=virtio,readonly=true", c.drives.user_data) == -1) {
			perror("asprintf");
			exit(EXIT_FAILURE);
		}

		execv(c.run_qemu, args);
		perror("execv");
		exit(EXIT_FAILURE);
	}

	free(args[2]);

	if ((console_conn = accept(console_listener, nullptr, nullptr)) == -1) {
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

	int server = setup_server();

	FILE *console = start_qemu(make_tmp_dir(), c);

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
