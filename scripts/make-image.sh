#!/bin/sh --
# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
set -eufo pipefail
case $0 in
/*) dir=${0%/*}/ ;;
*/*) dir=./${0%/*} ;;
*) dir=. ;;
esac
case $#,${1-} in
5,release | 4,live)
	shift
	version=$1 output_file=$2 root_fs_dir=$3 fat_file=${4-}
	;;
*)
	echo 'Usage: make-image.sh [release VERSION OUTPUT_FILE ROOT_FS_DIR FAT_IMAGE|live VERSION OUTPUT_FILE ROOT_FS_DIR]' >&2
	exit 1
	;;
esac

for i; do
	# Some characters not special to the shell can't be handled by this code.
	case $i in
	-* | *[!A-Za-z0-9._/+@-]*)
		printf 'Forbidden characters in "%s"\n' "$i" >&2
		exit 1
		;;
	'')
		printf 'Filename is empty\n' >&2
		exit 1
		;;
	esac
done

root_hashes=$(LC_ALL=C awk -f "${dir}/format-uuid.awk" < \
	"$root_fs_dir/rootfs.verity.roothash")
# The awk script produces output that is meant for field splitting
# and has no characters special for globbing.
# shellcheck disable=SC2086
set -- $root_hashes
if [ -n "$fat_file" ]; then
	"$dir/make-gpt.sh" "$output_file.tmp" \
		${fat_file:+"$fat_file:c12a7328-f81f-11d2-ba4b-00a0c93ec93b"} \
		"$root_fs_dir/rootfs.verity.superblock:verity:$1:Spectrum_$version.verity:1024MiB" \
		"$root_fs_dir/rootfs:root:$2:Spectrum_$version:20480MiB" \
		"/dev/null:verity:$3:_empty:1024MiB" \
		"/dev/null:root:$4:_empty:20480MiB"
else
	"$dir/make-gpt.sh" "$output_file.tmp" \
		${fat_file:+"$fat_file:c12a7328-f81f-11d2-ba4b-00a0c93ec93b"} \
		"$root_fs_dir/rootfs.verity.superblock:verity:$3:Spectrum_$version" \
		"$root_fs_dir/rootfs:root:$1:Spectrum_$version"
fi
mv -- "$output_file.tmp" "$output_file"
