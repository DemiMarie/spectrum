#!/usr/bin/awk -f
# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
BEGIN {
    update_url = ARGV[1];
    # Check for a GNU awk misfeature
    newline = "\n";
    # Reject URLs with control characters, query parameters, or fragments.
    # They *cannot* work and so are rejected to produce better error messages.
    # curl rejects control characters with "Malformed input to a URL function".
    # Fragment specifiers ("#") and query parameters ("?") break concatenating
    # /SHA256SUMS and /SHA256SUMS.sha256.asc onto the update URL.  Also, it is
    # simpler to reject update URLs that contain whitespace than to try to
    # escape them.
    if (update_url ~ /^[^\001-\040?#\x7F]+$/) {
        # Backslashes are special to systemd-sysupdate.
        # Use \\\\& because without the & the result is
        # not portable between GNU awk and non-GNU awk.
        gsub(/\\/, "\\\\&", update_url);
        # "&" and "\\" are special on the RHS of a sed substitution
        # and must be escaped with another backslash.  The delimiter
        # ("#" in this case) and "\n" must also be escaped, but they
        # were rejected above so don't bother.
        gsub(/[&\\]/, "\\\\&", update_url);
        printf "%s", update_url;
        exit 0;
    } else {
        print "Bad update URL from host: control characters, whitespace, query parameters, and fragment specifiers not allowed" > "/dev/stderr";
        exit 100;
    }
}
