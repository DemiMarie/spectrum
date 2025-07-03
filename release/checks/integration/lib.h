// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

#include <pthread.h>
#include <stdio.h>

struct config {
	const char *run_qemu;

	struct {
		const char *efi, *img, *user_data;
	} drives;

	struct {
		const char *optname, *optval, *console;
	} serial;
};

extern void test(struct config);

struct vm {
	pthread_t console_thread;
	FILE *console;
	int prompt_event;
};

struct vm start_qemu(struct config config);
