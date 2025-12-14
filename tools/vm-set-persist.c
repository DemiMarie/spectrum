// SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>
// SPDX-License-Identifier: EUPL-1.2+

#include <err.h>
#include <fcntl.h>
#include <libgen.h>
#include <unistd.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

// No <sys/stat.h> until musl declares stx_mnt_id.
#include <sys/syscall.h>

#include <linux/fs.h>
#include <linux/mount.h>
#include <linux/openat2.h>
#include <linux/stat.h>
#include <linux/unistd.h>

// Including trailing NUL bytes.
static const int MNT_ROOT_MAX_LEN = 43;
static const int SOURCE_MAX_LEN = 28;

static void set_mount_namespace(const char vm_id[static 1])
{
	char ns_path[28];
	int r = snprintf(ns_path, sizeof ns_path,
	                 "/run/vm/by-id/%s/ns/mnt", vm_id);

	if (r == -1)
		err(EXIT_FAILURE, "snprintf");
	if ((size_t)r >= sizeof ns_path)
		errx(EXIT_FAILURE, "VM ID unexpectedly long");

	if ((r = open(ns_path, O_RDONLY | O_CLOEXEC)) == -1)
		err(EXIT_FAILURE, "open");
	if (setns(r, CLONE_NEWNS) == -1)
		err(EXIT_FAILURE, "setns");
	close(r);
}

static void do_statx(const char path[static 1],
                     mode_t mode[static 1], uint64_t mnt_id[static 1])
{
	struct statx stx;

	if (syscall(__NR_statx, AT_FDCWD, path, AT_SYMLINK_NOFOLLOW,
	            STATX_MODE | STATX_MNT_ID_UNIQUE, &stx) == -1)
		err(EXIT_FAILURE, "statx");

	if (!(stx.stx_attributes & STATX_ATTR_MOUNT_ROOT)) {
		if (stx.stx_attributes_mask & STATX_ATTR_MOUNT_ROOT)
			errx(EXIT_FAILURE,
			     "VM disk-backed directory not mounted");

		errx(EXIT_FAILURE, "statx didn't return STATX_ATTR_MOUNT_ROOT");
	}

	if (!(stx.stx_mask & STATX_MNT_ID_UNIQUE))
		errx(EXIT_FAILURE, "statx didn't return STATX_MNT_ID_UNIQUE");
	if (!(stx.stx_mask & STATX_MODE))
		errx(EXIT_FAILURE, "statx didn't return STATX_MODE");

	*mode = stx.stx_mode;
	*mnt_id = stx.stx_mnt_id;
}

static int do_mount(const char source[static 1])
{
	int mnt, fs = syscall(__NR_fsopen, "btrfs", FSOPEN_CLOEXEC);
	if (fs == -1)
		err(EXIT_FAILURE, "fsopen");
	if (syscall(__NR_fsconfig, fs, FSCONFIG_SET_STRING,
	            "source", source, 0) == -1)
		err(EXIT_FAILURE, "FSCONFIG_SET_STRING source");
	if (syscall(__NR_fsconfig, fs, FSCONFIG_SET_FLAG,
	            "rw", nullptr, 0) == -1)
		err(EXIT_FAILURE, "FSCONFIG_SET_FLAG rw");
	if (syscall(__NR_fsconfig, fs, FSCONFIG_CMD_CREATE,
	            nullptr, nullptr, 0) == -1)
		err(EXIT_FAILURE, "FSCONFIG_CMD_CREATE");
	if ((mnt = syscall(__NR_fsmount, fs, FSMOUNT_CLOEXEC,
	                   MOUNT_ATTR_NOSUID | MOUNT_ATTR_NOSYMFOLLOW |
	                   MOUNT_ATTR_NOEXEC | MOUNT_ATTR_NODEV)) == -1)
		err(EXIT_FAILURE, "fsmount");
	close(fs);
	return mnt;
}

static void do_statmount(uint64_t mnt_id,
                         char mnt_root[static MNT_ROOT_MAX_LEN],
                         char source[static SOURCE_MAX_LEN])
{
	int r;
	char sm_buf[sizeof(struct statmount) +
	            MNT_ROOT_MAX_LEN + SOURCE_MAX_LEN];
	struct statmount *sm = (struct statmount *)sm_buf;
	struct mnt_id_req req = {
		.size = sizeof req,
		.mnt_id = mnt_id,
		.param = STATMOUNT_MNT_ROOT | STATMOUNT_SB_SOURCE,
	};

	if (syscall(__NR_statmount, &req, sm, sizeof sm_buf, 0) == -1)
		err(EXIT_FAILURE, "statmount");

	r = snprintf(mnt_root, MNT_ROOT_MAX_LEN, "%s", sm->str + sm->mnt_root);
	if (r == -1)
		err(EXIT_FAILURE, "snprintf");
	if (r >= MNT_ROOT_MAX_LEN)
		errx(EXIT_FAILURE, "unexpectedly long mnt_root");

	r = snprintf(source, SOURCE_MAX_LEN, "%s", sm->str + sm->sb_source);
	if (r == -1)
		err(EXIT_FAILURE, "snprintf");
	if (r >= SOURCE_MAX_LEN)
		errx(EXIT_FAILURE, "unexpectedly long sb_source");
}

static void do_rename(int mnt, const char dir_name[static 1],
                      const char old_name[static 1],
                      const char new_name[static 1], mode_t mode)
{
	struct open_how how = {
		.flags = O_PATH | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW,
		.resolve = RESOLVE_NO_MAGICLINKS | RESOLVE_IN_ROOT |
		           RESOLVE_NO_SYMLINKS | RESOLVE_NO_XDEV,
	};
	int dir = syscall(__NR_openat2, mnt, dir_name, &how, sizeof how);
	if (dir == -1)
		err(EXIT_FAILURE, "openat2");

	if (syscall(__NR_mkdirat, dir, new_name, mode) == -1)
		err(EXIT_FAILURE, "mkdirat");
	if (syscall(__NR_renameat2, dir, old_name, dir, new_name,
	            RENAME_EXCHANGE) == -1)
		err(EXIT_FAILURE, "renameat2");
}

int main(int argc, char *argv[])
{
	int mnt;
	mode_t mode;
	uint64_t mnt_id;
	char *disk_path, *dir_name, *old_name, *new_name,
	     mnt_root[MNT_ROOT_MAX_LEN], source[SOURCE_MAX_LEN];

	if (argc != 3) {
		fprintf(stderr, "Usage: vm-set-persist ID INSTANCE\n");
		exit(EXIT_FAILURE);
	}

	if (strchr(argv[1], '/'))
		errx(EXIT_FAILURE, "invalid VM ID");
	if (strchr(argv[2], '/'))
		errx(EXIT_FAILURE, "invalid persistent directory name");

	if (asprintf(&disk_path, "/run/fs/%s/disk", argv[1]) == -1)
		err(EXIT_FAILURE, "asprintf");
	if (asprintf(&new_name, "persist.%s", argv[2]) == -1)
		err(EXIT_FAILURE, "asprintf");

	set_mount_namespace(argv[1]);

	do_statx(disk_path, &mode, &mnt_id);
	do_statmount(mnt_id, mnt_root, source);

	if (!(dir_name = strdup(mnt_root)))
		err(EXIT_FAILURE, "strdup");
	dir_name = dirname(dir_name);
	old_name = basename(mnt_root);

	mnt = do_mount(source);

	do_rename(mnt, dir_name, old_name, new_name, mode);
}
