#!/bin/sh -eu
#
# SPDX-FileCopyrightText: 2023-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: EUPL-1.2+
#
# FIXME: It would be nice to replace this script with a program that
#        didn't have to redundantly copy everything so it's all in a
#        single directory structure, and could generate an EROFS image
#        based on source:dest mappings directly.

umask 0022 # for permissions
ex_usage() {
	echo "Usage: make-erofs.sh [options]... img < srcdest.txt" >&2
	exit 1
}

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

while read -r arg1; do
	read -r arg2 || ex_usage

	printf "%s" "$arg1"
	if [ "${arg1#/}" != "${arg2#/}" ]; then
		printf " -> %s" "$arg2"
	fi
	echo

	case $arg2 in
	(/)
		# Perform the copy.  -T means that if $arg1 and $root
		# are both directories, the contents of $arg1 are copied
		# to $root, rather than $arg1 itself being copied to $root.
		cp -RT -- "$arg1" "$root"

		# Nix store paths are read-only, so fix up permissions
		# so that subsequent copies can write to directories
		# created by the above copy.  This means giving all
		# directories 0755 permissions.
		find "$root" -type d -exec chmod 0755 -- '{}' +
		;;

	# The below simple version of dirname(1) can only handle
	# a subset of all paths, but this subset includes all of
	# the paths needed here.  Reject the others.
	(.|..|./*|../*|*/|*/.|*/..|*//*|*/./*|*/../*)
		echo 'Bad path (non-canonical)' >&2
		exit 1
		;;

	(*/*)
		# Create the parent directory if it doesn't already
		# exist.
		parent=${arg2%/*}
		if [ ! -d "$root/$parent" ]; then
			mkdir -p -- "$root/$parent"
		fi

		# Do the copy.  See above for why -T is needed.
		cp -RT -- "$arg1" "$root/$arg2"
		;;
	(*)
		# There is no parent directory to create.
		# Just do the copy.
		cp -RT -- "$arg1" "$root/$arg2"
		;;
	esac
done

mkfs.erofs -x-1 -b4096 --all-root "$@" "$root"
