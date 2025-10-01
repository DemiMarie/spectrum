// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
#include <assert.h>
#include <errno.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#include <fcntl.h>
#include <sys/types.h>
#include <dirent.h>

#include <linux/openat2.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <err.h>

static void checkdir(int fd)
{
	DIR *d = fdopendir(fd);
	if (d == NULL)
		err(EXIT_FAILURE, "fdopendir");
	// If there is an I/O error while there are dirty pages outstanding,
	// the dirty pages are silently discarded.  This means that the contents
	// of the filesystem can change behind userspace's back.  Flush all
	// dirty pages in the filesystem with the directory to prevent this.
	if (syncfs(fd) != 0)
		err(EXIT_FAILURE, "syncfs");
	for (;;) {
		errno = 0;
		struct dirent *entry = readdir(d);
		if (entry == NULL) {
			if (errno)
				err(EXIT_FAILURE, "readdir");
			break;
		}
		assert(entry->d_reclen > offsetof(struct dirent, d_name));
		size_t len = strnlen(entry->d_name, entry->d_reclen - offsetof(struct dirent, d_name));
		if (entry->d_name[0] == '.')
			if (len == 1 || (len == 2 && entry->d_name[1] == '.'))
				continue;
		unsigned char c = (unsigned char)entry->d_name[0];
		if (!((c >= 'A' && c <= 'Z') ||
		      (c >= 'a' && c <= 'z')))
			errx(EXIT_FAILURE, "Filename must begin with an ASCII letter");
		for (size_t i = 1; i < len; ++i) {
			c = (unsigned char)entry->d_name[i];
			if (!((c >= 'A' && c <= 'Z') ||
			      (c >= 'a' && c <= 'z') ||
			      (c >= '0' && c <= '9') ||
			      (c == '_') ||
			      (c == '-') ||
			      (c == '.'))) {
				if (c >= 0x20 && c <= 0x7E)
					errx(EXIT_FAILURE, "Forbidden subsequent character in filename: '%c'", (int)c);
				else
					errx(EXIT_FAILURE, "Forbidden subsequent character in filename: byte %d", (int)c);
			}
		}
		if (entry->d_name[len - 1] == '.')
			errx(EXIT_FAILURE, "Filename must not end with a '.'");
		if (entry->d_type != DT_REG)
			errx(EXIT_FAILURE, "Entry contains non-regular file %s", entry->d_name);
	}
	closedir(d);
}

int main(int argc, char **argv)
{
	for (int i = 1; i < argc; ++i) {
		int fd = open(argv[i], O_DIRECTORY|O_RDONLY|O_CLOEXEC|O_NOFOLLOW);
		if (fd < 0)
			err(EXIT_FAILURE, "open(%s)", argv[i]);
		checkdir(fd);
	}
	return 0;
}
