#!/bin/sh -eu
#
# SPDX-FileCopyrightText: 2023-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: EUPL-1.2+
#
# FIXME: It would be nice to replace this script with a program that
#        didn't have to redundantly copy everything so it's all in a
#        single directory structure, and could generate an EROFS image
#        based on source:dest mappings directly.

ex_usage() {
	echo "Usage: make-erofs.sh [options]... img < srcdest.txt" >&2
	exit 1
}

for img; do :; done
if [ -z "${img-}" ]; then
	ex_usage
fi

root="$(mktemp -d -- "$img.tmp.XXXXXXXXXX")"
trap 'chmod -R +w -- "$root" && rm -rf -- "$root"' EXIT

while read -r arg1; do
	read -r arg2 || ex_usage

	printf "%s" "$arg1"
	if [ "${arg1#/}" != "${arg2#/}" ]; then
		printf " -> %s" "$arg2"
	fi
	echo

	if [ "$arg2" = / ]; then
		cp -RT -- "$arg1" "$root"
		# Nix store paths are read-only, so fix up permissions
		# so that subsequent copies can write to directories
		# created by the above copy.  This means giving all
		# directories 0755 permissions.
		find "$root" -type d -exec chmod 0755 -- '{}' +
		continue
	fi

	parent=$(dirname "$arg2")
	mkdir -p -- "$root/$parent"
	cp -RT -- "$arg1" "$root/$arg2"
done

mkfs.erofs -x-1 -b4096 --all-root "$@" "$root"
