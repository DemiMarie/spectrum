// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>

#include <fcntl.h>

[[gnu::fd_arg(1)]]
int clear_cloexec(int fd)
{
	int flags = fcntl(fd, F_GETFD);
	if (flags == -1)
		return -1;
	return fcntl(fd, F_SETFD, flags & ~FD_CLOEXEC);
}
