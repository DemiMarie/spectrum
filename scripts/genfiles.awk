# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
BEGIN {
	RS = "\n";
	FS = "\t";
	modes["120000"] = "symlink";
	modes["100644"] = "regular";
	modes["100755"] = "regular";
}

function fail(msg) {
	# Awk will run END blocks even after exit.
	# The END block checks this variable and
	# immediately exits if it is nonzero.
	exit_code = 1;
	print msg > "/dev/stderr";
	exit 1;
}

# Extract data from built-in variables.
{
	filename = $2;
	raw_mode = $1;
	# Awk autocreates empty string entries if the key is invalid,
	# but the code exits in this case so that is okay.
	mode = modes[raw_mode];
}

filename !~ /^[[:alnum:]_./-]+$/ {
	fail("filename '" filename "' has forbidden characters");
}

# Skip license files
filename ~ /\.license$/ { next }

filename ~ /^image\/etc\/s6-rc\// {
	if (mode != "regular") {
		fail("s6-rc-compile input '" filename "' isn't a regular file");
	}
	rc_files[rc_count++] = filename;
	next;
}

mode == "symlink" {
	symlinks[symlink_count++] = filename;
	next;
}

mode == "regular" {
	files[file_count++] = filename;
	next;
}

{ fail("File '" filename "' is not regular file or symlink (mode " raw_mode ")"); }

END {
	if (exit_code) {
		exit exit_code;
	}
	printf ("# SPDX-" \
"License-Identifier: CC0-1.0\n" \
"# SPDX-" \
"FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>\n" \
"\n" \
"FILES =");
	for (array_index = 0; array_index < file_count; array_index += 1) {
		printf " \\\n\t%s", files[array_index];
	}
	# GNU Make uses the modification time of the *target* of a symlink,
	# rather than the modification time of the symlink itself.  It can be told
	# to *also* use the symlink's modification time, but not to *only* use
	# the symlink's modification time.  However, these symlinks will generally
	# be broken, so make will not be able to dereference the symlink.
	# Therefore, using these symlinks as make dependencies won't work.
	printf ("\n\n" \
"LINKS =");
	for (array_index = 0; array_index < symlink_count; array_index += 1) {
		printf " \\\n\t%s", symlinks[array_index];
	}
	printf "\n\nS6_RC_FILES =";
	for (array_index = 0; array_index < rc_count; array_index += 1) {
		printf " \\\n\t%s", rc_files[array_index];
	}
	print "";
}
