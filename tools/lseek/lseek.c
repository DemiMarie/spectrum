// SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>
// SPDX-License-Identifier: EUPL-1.2+

#include <err.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdnoreturn.h>
#include <string.h>
#include <unistd.h>

#include <sys/types.h>

noreturn static void ex_usage(void)
{
	fputs("Usage: lseek [ -C | -E | -S ] fd offset prog...\n", stderr);
	exit(EXIT_FAILURE);
}

int main(int argc, char *argv[])
{
	int opt, whence = SEEK_CUR;
	long fd, offset;

	while ((opt = getopt(argc, argv, "+CES")) != -1) {
		switch (opt) {
		case 'C':
			whence = SEEK_CUR;
			break;
		case 'E':
			whence = SEEK_END;
			break;
		case 'S':
			whence = SEEK_SET;
			break;
		default:
			ex_usage();
		}
	}

	if (optind > argc - 2)
		ex_usage();

	fd = strtol(argv[optind++], NULL, 10);
	if (fd < 0 || fd > INT_MAX)
		errx(EXIT_FAILURE, "%s", strerror(EBADF));

	errno = 0;
	offset = strtol(argv[optind++], NULL, 10);
	if (errno)
		err(EXIT_FAILURE, "bad offset: %s", argv[optind - 1]);
	if (offset != (off_t)offset)
		errx(EXIT_FAILURE, "%s", strerror(EINVAL));

	if (lseek(fd, offset, whence) == -1)
		err(EXIT_FAILURE, NULL);

	execvp(argv[optind], argv + optind);
	err(EXIT_FAILURE, "exec");
}
