#!/bin/sh --
# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
set -euo pipefail
export LC_ALL=C LANGUAGE=C
dir=$(git rev-parse --show-toplevel)
cd -- "$dir"
for i in host/rootfs img/app vm/sys/net; do
    output_file=$i/file-list.mk
    {
        git -C "$i" -c core.quotePath=true ls-files $'--format=%(objectmode)\t%(path)' -- image |
        sort -t $'\t' -k 2
    } |
    awk -f scripts/genfiles.awk > "$output_file.tmp"
    if [ -f "$output_file" ]; then
        # Avoid changing output file if it is up to date, as that
        # would cause unnecessary rebuilds.
        if cmp -s -- "$output_file.tmp" "$output_file"; then
            rm -- "$output_file.tmp"
            continue
        else
            astatus=$?
            if [ "$astatus" != 1 ]; then exit "$astatus"; fi
        fi
    fi
    mv -- "$output_file.tmp" "$output_file"
done
