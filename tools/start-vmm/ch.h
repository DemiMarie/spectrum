// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022-2024 Alyssa Ross <hi@alyssa.is>

#include <stdint.h>

struct net_config {
	int fd;
	char id[18];
	uint8_t mac[6];
};
