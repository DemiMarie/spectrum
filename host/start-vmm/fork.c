// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>

#include <errno.h>
#include <stdlib.h>
#include <unistd.h>

#include <sys/wait.h>

// Positive return value: in grandparent, pid of grandchild.
// 0: in grandchild.
// Negative return value: errno.
int double_fork(void)
{
	int fd[2], v;
	size_t acc = 0;
	ssize_t r;
	pid_t child;

	if (pipe(fd) == -1)
		return -errno;

	switch (child = fork()) {
	case -1:
		v = errno;
		close(fd[0]);
		close(fd[1]);
		return -v;
	case 0:
		close(fd[0]);
		switch ((v = fork())) {
		case 0:
			close(fd[1]);
			return 0;
		case -1:
			v = -errno;
			[[fallthrough]];
		default:
			do {
				r = write(fd[1], (char *)&v + acc, sizeof v - acc);
			} while ((r != -1 || errno == EINTR) && (acc += r) < sizeof v);
			exit(v < 0 || r == -1);
		}
	default:
		close(fd[1]);
		do {
			r = read(fd[0], (char *)&v + acc, sizeof v - acc);
		} while ((r != -1 || errno == EINTR) && (acc += r) < sizeof v);
		if (r == -1) {
			v = -errno;
			kill(child, SIGKILL);
			waitpid(child, NULL, 0);
		}
		close(fd[0]);
		return v;
	}
}
