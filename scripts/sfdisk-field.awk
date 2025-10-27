#!/usr/bin/awk -f
#
# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2022, 2024 Alyssa Ross <hi@alyssa.is>

BEGIN {
	types["root.aarch64"] = "b921b045-1df0-41c3-af44-4c6f280d3fae"
	types["root.x86_64"] = "4f68bce3-e8cd-4db1-96e7-fbcaf984b709"
	types["verity.aarch64"] = "df3300ce-d69f-4c92-978c-9bfb0f38d820"
	types["verity.x86_64"] = "2c7357ed-ebd2-46d9-aec1-23d437ec2bf5"

	# Field #1 is the partition path, which make-gpt.sh will turn into
	# the size field.  Since it's handled elsewhere, we skip that
	# first field.
	skip=1

	split("type uuid name", keys)
	split(partition, fields, ":")

	arch = ENVIRON["ARCH"]
	if (!arch) {
		"uname -m" | getline _arch
		if (!close("uname -m"))
			arch = _arch
	}

	comma = ""
	for (n in fields) {
		if (n <= skip)
			continue

		if (keys[n - skip] == "type") {
			if (uuid = types[fields[n] "." arch])
				fields[n] = uuid
		}

		printf ",%s%s=%s", comma, keys[n - skip], fields[n]
	}
}
