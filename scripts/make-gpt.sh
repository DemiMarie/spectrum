# SPDX-FileCopyrightText: 2021-2023 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie
# SPDX-License-Identifier: EUPL-1.2+
#
# usage: bash make-gpt.sh GPT_PATH PATH:PARTTYPE[:PARTUUID[:PARTLABEL]]...

set -xeuo pipefail
ONE_MiB=1048576

# Prints the number of 1MiB blocks required to store the file named
# $1.  We use 1MiB blocks because that's what sfdisk uses for
# alignment.  It would be possible to get a slightly smaller image
# using actual normal-sized 512-byte blocks, but it's probably not
# worth it to configure sfdisk to do that.
sizeMiB() {
	wc -c "$1" | awk -v ONE_MiB=$ONE_MiB \
		'{printf "%d\n", ($1 + ONE_MiB - 1) / ONE_MiB}'
}

# Copies from path $3 into partition number $2 in partition table $1.
fillPartition() {
	start="$(sfdisk -J "$1" | jq -r --argjson index "$2" \
		'.partitiontable.partitions[$index].start * 512')"

	# GNU cat will use copy_file_range(2) if possible, whereas dd
	# will always do a userspace copy, which is significantly slower.
	lseek -S 1 "$start" cat "$3" 1<>"$1"
}

scriptsDir="$(dirname "$0")"

out="$1"
shift

table="label: gpt"

# Keep 1MiB free at the start, and 1MiB free at the end.
gptBytes=$((ONE_MiB * 2))
for partition; do
	if [[ "$partition" =~ :([1-9][0-9]*)MiB$ ]]; then
		sizeMiB=${BASH_REMATCH[1]}
		partition=${partition%:*}
	else
		sizeMiB=$(sizeMiB "${partition%%:*}")
	fi
	table+=$'\n'"size=${sizeMiB}MiB,$(awk -f "$scriptsDir/sfdisk-field.awk" -v partition="$partition")"
	gptBytes=$((gptBytes + sizeMiB * ONE_MiB))
done

rm -f "$out"
truncate -s "$gptBytes" "$out"
sfdisk --no-reread --no-tell-kernel "$out" <<EOF
$table
EOF

n=0
for partition; do
	fillPartition "$out" "$n" "${partition%%:*}"
	n=$((n + 1))
done
