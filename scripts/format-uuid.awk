# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
function format_uuid(arg) {
	if (arg in found_so_far) {
		fail("Duplicate UUID, try changing the image (by even 1 bit)");
	}
	found_so_far[arg] = 1;
	print (substr(arg, 1, 8) "-" \
	       substr(arg, 9, 4) "-" \
	       substr(arg, 13, 4) "-" \
	       substr(arg, 17, 4) "-" \
	       substr(arg, 21, 12));
}

function fail(msg) {
	print msg > "/dev/stderr";
	exit 1;
}

BEGIN {
	FS = "";
	RS = "\n";
	if ((getline) != 1)
		fail("Empty input file");
	roothash = $0;
	if (roothash !~ /^[a-f0-9]{64}$/)
		fail("Invalid root hash");
	if (getline)
		fail("Junk after root hash");
	found_so_far[""] = "";
	for (i = 1; i != 49; i += 16) {
		format_uuid(substr($0, i, 32));
	}
	format_uuid(substr($0, 49, 16) substr($0, 1, 16));
}
