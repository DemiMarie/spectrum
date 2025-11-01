// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

#include "lib.h"

#include <stdlib.h>

void test(struct config c)
{
	struct vm *vm = start_qemu(c);
	start_console_thread(vm, "~ # ");
	wait_for_prompt(vm);

	if (fputs("set -euxo pipefail && "
	          "(tail -Fc +0 /run/log/current &) && "
	          "mkdir /run/mnt && "
	          "mount \"$(findfs UUID=a7834806-2f82-4faf-8ac4-4f8fd8a474ca)\" /run/mnt && "
	          "s6-rc -bu change vmm-env && "
	          "vm-import user /run/mnt/vms && "
	          "(tail -Fc +0 /run/*.log &) && "
	          "s6-svc -O /run/vm/by-name/user.portal/service && "
	          "vm-start \"$(basename \"$(readlink /run/vm/by-name/user.portal)\")\" && "
	          "s6-svwait -d /run/vm/by-name/user.portal/service\n",
	          vm_console_writer(vm)) == EOF) {
		fputs("error writing to console\n", stderr);
		exit(EXIT_FAILURE);
	}

	wait_for_prompt(vm);
}
