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

mkfs.erofs -x-1 -b4096 --all-root "$@" "$root"
