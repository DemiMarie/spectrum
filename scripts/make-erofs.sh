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

	# The below simple version of dirname(1) can only handle
	# a subset of all paths, but this subset includes all of
	# the ones passed in practice other than /.
	case $arg2 in
	(*/*) parent=${arg2%/*};;
	(*) parent=.;;
	esac

	awk -v parent="$parent" -v root="$root" 'BEGIN {
		n = split(parent, components, "/")
		for (i = 1; i <= n; i++) {
			printf "%s/", root
			for (j = 1; j <= i; j++)
				printf "%s/", components[j]
			print
		}
	}' | xargs -rd '\n' chmod +w -- 2>/dev/null || :
	mkdir -p -- "$root/$parent"

	cp -RT -- "$arg1" "$root/$arg2"
done

mkfs.erofs -x-1 -b4096 --all-root "$@" "$root"
