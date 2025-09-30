#!/bin/sh -eu
#
# SPDX-FileCopyrightText: 2023-2025 Alyssa Ross <hi@alyssa.is>
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

	# Ensure any existing directories we want to write into are writable.
	(
		set --
		while :; do
			abs="$root/$parent"
			if [ -e "$abs" ] && ! [ -w "$abs" ]; then
				set -- "$abs" "$@"
			fi

			# shellcheck disable=SC2030 # shadowed on purpose
			case "$parent" in
				*/*) parent="${parent%/*}" ;;
				*) break ;;
			esac
		done

		if [ "$#" -ne 0 ]; then
			chmod +w -- "$@"
		fi
	)

	# shellcheck disable=SC2031 # shadowed in subshell on purpose
	if ! [ -e "$root/$parent" ]; then
		mkdir -p -- "$root/$parent"
	fi

	cp -RT -- "$arg1" "$root/$arg2"
done

mkfs.erofs -x-1 -b4096 --all-root "$@" "$root"
