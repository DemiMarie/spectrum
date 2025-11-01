// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

#include "lib.h"

void test(struct config c)
{
	struct vm *vm;

	c.serial = (typeof(c.serial)) {
		.optname = "-device",
		.optval = "usb-serial,chardev=socket",
		.console = "ttyUSB0",
	};

	vm = start_qemu(c);
	start_console_thread(vm, "~ # ");
	wait_for_prompt(vm);
}
