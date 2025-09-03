# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

include $(basedir)/lib/common.mk
include file-list.mk
BUILD_FILES += build/etc/s6-rc
dest = build/rootfs.erofs

all:
.PHONY: all
$(dest): $(basedir)/scripts/make-erofs.sh $(PACKAGES_FILE) $(FILES) $(BUILD_FILES) build/empty build/fifo file-list.mk
	set -euo pipefail; ( \
	    cat $(PACKAGES_FILE);\
	    for file in $(FILES) $(LINKS); do printf '%s\n%s\n' "$$file" "$${file#image/}"; done;\
	    for file in $(BUILD_FILES); do printf '%s\n%s\n' "$$file" "$${file#build/}"; done;\
	    for dir in $(DIRS); do printf 'build/empty\n%s\n' "$$dir"; done;\
	    for fifo in $(FIFOS); do printf 'build/fifo\n%s\n' "$$fifo"; done;\
	) | $(basedir)/scripts/make-erofs.sh $@

clean:
	-chmod -Rf +w build
	rm -rf build
.PHONY: clean
	false

build/fifo:
	mkdir -p build
	mkfifo -m 0600 $@

build/empty:
	mkdir -p $@

# s6-rc-compile's input is a directory, but that doesn't play nice
# with Make, because it won't know to update if some file in the
# directory is changed, or a file is created or removed in a
# subdirectory.  Using the whole source directory could also end up
# including files that aren't intended to be part of the input, like
# temporary editor files or .license files.  So for all these reasons,
# only explicitly listed files are made available to s6-rc-compile.
build/etc/s6-rc: $(S6_RC_FILES) file-list.mk
	mkdir -p build/etc
	rm -rf $@
	set -uo pipefail; \
	dir=$$(mktemp -d) && \
	{ tar -c $(S6_RC_FILES) | tar -C "$$dir" -x --strip-components 3;} && \
	s6-rc-compile $@ $$dir; \
	exit=$$?; rm -r $$dir; exit $$exit
