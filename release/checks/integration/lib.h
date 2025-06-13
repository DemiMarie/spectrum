// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

#include <stdio.h>

struct config {
	const char *run_qemu;

	struct {
		const char *efi, *img, *user_data;
	} drives;
};

extern void test(struct config);

FILE *start_qemu(struct config config);
