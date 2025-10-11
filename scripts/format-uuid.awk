function format_uuid(arg) {
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
	for (i = 1; i != 65; i += 16) {
		s = substr($0, i, 32);
		if (s in found_so_far) {
			fail("Duplicate UUID, try changing the image (by even 1 bit)");
		}
		found_so_far[s] = 1;
		format_uuid(s)
	}
}
