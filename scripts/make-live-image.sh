#!/bin/sh --
# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
set -euo pipefail
case $0 in
(/*) dir=${0%/*}/;;
(*/*) dir=./${0%/*};;
(*) dir=.;;
esac
usage () {
  echo 'Usage: make-live-image.sh [release|live] OUTPUT_FILE' >&2
  exit 1
}
if [ "$#" != 2 ]; then usage; fi
file_type=$1 output_file=$2
for i in "$ROOT_FS" "$ROOT_FS_VERITY" "$ROOT_FS_VERITY_ROOTHASH" "$VERSION"; do
  # Some characters not special to the shell can't be handled by this code.
  case $i in
  (-*|*[!A-Za-z0-9._/+@-]*) printf 'Forbidden characters in "%s"\n' "$i" >&2; exit 1;;
  esac
done
root_hashes=$(LC_ALL=C awk -f "${dir}/format-uuid.awk" < "$ROOT_FS_VERITY_ROOTHASH")
# The awk script produces output that is meant for field splitting
# and has no characters special for globbing.
# shellcheck disable=SC2086
set -- $root_hashes
case $file_type in
(release)
  "$dir/make-gpt.sh" "$output_file.tmp" \
    build/boot.fat:c12a7328-f81f-11d2-ba4b-00a0c93ec93b \
    "$ROOT_FS_VERITY:verity:$1:Spectrum_$VERSION.verity:1024MiB" \
    "$ROOT_FS:root:$2:Spectrum_$VERSION:20480MiB" \
    "/dev/null:verity:$3:_empty:1024MiB" \
    "/dev/null:root:$4:_empty:20480MiB"
  ;;
(live)
  "$dir/make-gpt.sh" "$output_file.tmp" \
    "$ROOT_FS_VERITY:verity:$1:Spectrum_$VERSION.verity" \
    "$ROOT_FS:root:$2:Spectrum_$VERSION";;
(*) usage;;
esac
mv -- "$output_file.tmp" "$output_file"
