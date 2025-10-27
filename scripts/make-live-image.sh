#!/bin/sh --
# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
set -euo pipefail
if [ ! -f build/rootfs.verity.superblock ]; then
  echo 'No superblock found' >&2
  exit 1
fi
case $0 in
(/*) dir=${0%/*}/;;
(*/*) dir=./${0%/*};;
(*) dir=.;;
esac
usage () {
  echo 'Usage: make-live-image.sh [release|live] OUTPUT_FILE ROOT_FILESYSTEM' >&2
  exit 1
}
if [ "$#" != 3 ]; then usage; fi
file_type=$1 output_file=$2 root_filesystem=$3
root_hashes=$(LC_ALL=C awk -f "${dir}/format-uuid.awk" < build/rootfs.verity.roothash)
# The awk script produces output that is meant for field splitting
# and has no characters special for globbing.
# shellcheck disable=SC2086
set -- $root_hashes
case $file_type in
(release)
  "$dir/make-gpt.sh" "$output_file.tmp" \
    build/boot.fat:c12a7328-f81f-11d2-ba4b-00a0c93ec93b \
    "build/rootfs.verity.superblock:verity:$1:Spectrum_$VERSION.verity:1024MiB" \
    "$root_filesystem:root:$2:Spectrum_$VERSION:20480MiB" \
    "/dev/null:verity:$3:_empty:1024MiB" \
    "/dev/null:root:$4:_empty:20480MiB"
  ;;
(live)
  "$dir/make-gpt.sh" "$output_file.tmp" \
    "build/rootfs.verity.superblock:verity:$1:Spectrum_$VERSION.verity" \
    "$root_filesystem:root:$2:Spectrum_$VERSION";;
(*) usage;;
esac
mv -- "$output_file.tmp" "$output_file"
