#!/usr/bin/awk -f
#
# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2022, 2024-2025 Alyssa Ross <hi@alyssa.is>

BEGIN {
	types["root.aarch64"] = "b921b045-1df0-41c3-af44-4c6f280d3fae"
	types["root.x86_64"] = "4f68bce3-e8cd-4db1-96e7-fbcaf984b709"
	types["verity.aarch64"] = "df3300ce-d69f-4c92-978c-9bfb0f38d820"
	types["verity.x86_64"] = "2c7357ed-ebd2-46d9-aec1-23d437ec2bf5"

	# Field #1 is the partition path, which is read by make-gpt.sh
	# but not relevant for running sfdisk, so skip it.
	skip=1

	split("type uuid name size", keys)
	split(partition, fields, ":")

	arch = ENVIRON["ARCH"]
	if (!arch) {
		"uname -m" | getline _arch
		if (!close("uname -m"))
			arch = _arch
	}

	for (n in fields) {
		if (n <= skip)
			continue

		if (keys[n - skip] == "type") {
			if (uuid = types[fields[n] "." arch])
				fields[n] = uuid
		} else if (keys[n - skip] == "size") {
			if (fields[n] < size) {
				printf "%s MiB partition content is too big for %s MiB partition\n",
					size, fields[n] > "/dev/stderr"
				exit 1
			}

			size = fields[n]
			continue # Handled at the end.
		}

		printf "%s=%s,", keys[n - skip], fields[n]
	}

	# Always output a size field, either supplied in input or
	# default value of the size variable.
	printf "size=%s\n", size
}
