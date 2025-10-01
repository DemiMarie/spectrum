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
#include <unistd.h>

#include <err.h>

[[noreturn]] static void bad_char(char c, char *msg_component)
{
	if (c >= 0x20 && c <= 0x7E)
		errx(EXIT_FAILURE, "Forbidden %s character in filename: '%c'",
		     msg_component, (int)c);
	errx(EXIT_FAILURE,
	     "Forbidden %s character in filename: byte %d",
	     msg_component, (int)(unsigned char)c);
}

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
	bool changed = false;
	for (;;) {
		errno = 0;
		struct dirent *entry = readdir(d);
		if (entry == NULL) {
			if (errno)
				err(EXIT_FAILURE, "readdir");
			break;
		}
		const char *ptr = entry->d_name;
		if (ptr[0] == '.') {
			if (ptr[1] == '\0')
				continue;
			if (ptr[1] == '.' && ptr[2] == '\0')
				continue;
			// systemd-sysupdate uses these for temporary files.
			// It normally cleans them up itself, but if there is an error
			// it does not always clean them up.  I'm not sure if it is
			// guaranteed to clean up temporary files from a past run, so
			// delete them instead of returning an error.
			if (unlinkat(fd, ptr, 0))
				err(EXIT_FAILURE, "Failed to unlink temporary file");
			changed = true;
			continue;
		}
		char c = ptr[0];
		if (!((c >= 'A' && c <= 'Z') ||
		      (c >= 'a' && c <= 'z')))
			bad_char(c, "initial");
		while ((c = *++ptr)) {
			if (!((c >= 'A' && c <= 'Z') ||
			      (c >= 'a' && c <= 'z') ||
			      (c >= '0' && c <= '9') ||
			      (c == '_') ||
			      (c == '-') ||
			      (c == '.'))) {
				bad_char(c, "subsequent");
			}
		}
		// Empty filenames are rejected as having a bad initial character,
		// and POSIX forbids them from being returned anyway.  Therefore,
		// this cannot be out of bounds.
		if (ptr[-1] == '.')
			errx(EXIT_FAILURE, "Filename %s ends with a '.'", entry->d_name);
		if (entry->d_type != DT_REG)
			errx(EXIT_FAILURE, "Entry contains non-regular file %s", entry->d_name);
	}
	// fsync() the directory if it was changed, to avoid the above
	// cache-incoherency problem.
	if (changed && fsync(fd))
		errx(EXIT_FAILURE, "fsync");
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
