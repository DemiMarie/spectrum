#!/bin/sh -eu
#
# SPDX-FileCopyrightText: 2023-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
# SPDX-License-Identifier: EUPL-1.2+
#
# FIXME: It would be nice to replace this script with a program that
#        didn't have to redundantly copy everything so it's all in a
#        single directory structure, and could generate an EROFS image
#        based on source:dest mappings directly.

umask 0022 # for permissions
ex_usage() {
	echo "Usage: make-erofs.sh [s6|systemd] [options]... img < srcdest.txt" >&2
	exit 1
}

case ${1-bad} in
(s6|systemd) init_type=$1; shift;;
(*) ex_usage;;
esac
for img; do :; done
if [ -z "${img-}" ]; then
	ex_usage
fi

superroot="$(mktemp -d -- "$img.tmp.XXXXXXXXXX")"
cat > "$superroot/input_files"
exec < "$superroot/input_files"
trap 'chmod -R +w -- "$root" && rm -rf -- "$superroot"' EXIT
# $superroot has 0700 permissions, so create a subdirectory
# with correct (0755) permissions and do all work there.
root=$superroot/real_root
mkdir -- "$root"

check_path () {
	# Various code can only handle paths that do not end with /
	# and are in canonical form.  Reject others.
	for i; do
		case $i in
		(''|.|..|./*|../*|*/|*/.|*/..|*//*|*/./*|*/../*)
			printf 'Path "%s" is /, //, empty, or not canonical\n' "$i" >&2
			exit 1
			;;
		(*[!A-Za-z0-9._@+/-]*)
			printf 'Path "%s" has forbidden characters\n' "$i" >&2
			exit 1
			;;
		(-*)
			printf 'Path "%s" begins with -\n' "$i" >&2
			exit 1
			;;
		(/nix/store/*|[!/]*)
			:
			;;
		(*)
			printf 'Path "%s" is neither relative nor a Nix store path\n' "$i" >&2
			exit 1
			;;
		esac
	done
}

while read -r arg1; do
	read -r arg2 || ex_usage

	printf "%s" "$arg1"
	if [ "${arg1#/}" != "${arg2#/}" ]; then
		printf " -> %s" "$arg2"
	fi
	echo

	if [ "$arg2" = / ]; then
		check_path "$arg1"
		cp -RT -- "$arg1" "$root"
		# Nix store paths are read-only, so fix up permissions
		# so that subsequent copies can write to directories
		# created by the above copy.  This means giving all
		# directories 0755 permissions.
		find "$root" -type d -exec chmod 0755 -- '{}' +
		continue
	fi

	check_path "$arg1" "$arg2"

	# The below simple version of dirname(1) can only handle
	# a subset of all paths, but this subset includes all of
	# the paths that check_path doesn't reject.
	case $arg2 in
	(*/*)
		# Create the parent directory if it doesn't already
		# exist.
		parent=${arg2%/*}
		if [ ! -d "$root/$parent" ]; then
			mkdir -p -- "$root/$parent"
		fi
		;;
	(*) :;; # parent $root which definitely exists
	esac
	cp -RT -- "$arg1" "$root/$arg2"
done

# Ensure that the permissions in the image are independent
# of those in the git repository or Nix store, except for
# the executable bit.  In particular, the mode of those
# outside the Nix store might depend on the user's umask.
# While the image itself is strictly read-only, it makes
# sense to populate an overlayfs over /etc and /var, and
# this overlayfs should be writable by root and readable
# by all users.  The remaining paths should not be writable
# by anyone, but should be world-readable.
find "$root" \
  -path "$root/nix/store" -prune -o \
  -path "$root/etc" -prune -o \
  -path "$root/var" -prune -o \
  -type l -o \
  -type d -a -perm 0555 -o \
  -type f -a -perm 0444 -o \
  -execdir chmod ugo-w,ugo+rX -- '{}' +
find "$root/etc" "$root/var" ! -type l -execdir chmod u+w,go-w,ugo+rX -- '{}' +
chmod 0755 "$root"

# Fix permissions on / so that the subsequent commands work
chmod 0755 "$root"

# Create the basic mount points for pseudo-filesystems and tmpfs filesystems.
# These should always be mounted over, so use 0400 permissions for them.
# 0000 would be better, but it breaks mkfs.erofs as it tries to open the
# directories for reading.
mkdir -m 0400 "$root/dev" "$root/proc" "$root/run" "$root/sys" "$root/tmp"

# Create /var/cache, /var/log, and /var/spool directly.
mkdir -m 0755 \
	"$root/home" \
	"$root/var/cache" \
	"$root/var/log" \
	"$root/var/spool"

# Create symbolic links that are always expected to exist.
# They certainly need to exist in img/app, and it makes life
# simpler for contributors if they are simply there always.
chmod 0755 "$root/usr"
ln -sf ../proc/self/mounts "$root/etc/mtab"
case $init_type in
(s6)
	# Create /var/tmp for programs that use it.
	ln -sf ../tmp "$root/var/tmp"
	# Cause s6-linux-init to create /run/lock and /run/user
	# with the correct mode (0755).
	mkdir -m 0755 \
		"$root/etc/s6-linux-init/run-image/lock" \
		"$root/etc/s6-linux-init/run-image/user"
	;;
(systemd)
	# systemd expects /srv to exist
	# and creates /var/tmp itself
	mkdir -m 0755 "$root/srv"
	;;
(*)
	echo 'internal error: bad init type' >&2
	exit 1
	;;
esac
ln -sf ../run "$root/var/run"
ln -sf ../run/lock "$root/var/lock"
ln -sf bin "$root/usr/sbin"
ln -sf lib "$root/usr/lib64"
ln -sf usr/bin "$root/bin"
ln -sf usr/bin "$root/sbin"
ln -sf usr/lib "$root/lib"
ln -sf usr/lib "$root/lib64"
chmod 0555 "$root/usr"

# Make the erofs image.
mkfs.erofs -x-1 -b4096 --all-root "$@" "$root"
