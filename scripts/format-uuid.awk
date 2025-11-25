# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
function format_uuid(arg) {
	print (substr(arg, 1, 8) "-" \
	       substr(arg, 9, 4) "-" \
	       substr(arg, 13, 4) "-" \
	       substr(arg, 17, 4) "-" \
	       substr(arg, 21, 12));
}

BEGIN {
	FS = "";
	if (getline != 1) {
		print "Empty input file" > "/dev/stderr";
                exit 1;
        }
        format_uuid(substr($0, 1, 32));
        format_uuid(substr($0, 33, 32));
}
