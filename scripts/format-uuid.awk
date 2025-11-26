# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
BEGIN {
	print (substr(ARGV[1], 1, 8) "-" \
	       substr(ARGV[1], 9, 4) "-" \
	       substr(ARGV[1], 13, 4) "-" \
	       substr(ARGV[1], 17, 4) "-" \
	       substr(ARGV[1], 21, 12));
}
