// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

#include "lib.h"

#include <stdlib.h>
#include <string.h>

void test(struct config c)
{
	struct vm *vm;

	// Spectrum's live image doesn't work right now.
	// Mark the test as skipped.
	exit(77);

	c.drives.img = getenv_or_die("COMBINED_PATH");

	vm = start_qemu(c);

	start_console_thread(vm, "GNU GRUB ");
	wait_for_prompt(vm);

	start_console_thread(vm, "~ # ");

	// Assume that Try Spectrum is the first menu entry.
	if (fputc('\n', vm_console_writer(vm)) == EOF) {
		fputs("error writing to console\n", stderr);
		exit(EXIT_FAILURE);
	}

	wait_for_prompt(vm);
}
