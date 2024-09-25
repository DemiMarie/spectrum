// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022-2024 Alyssa Ross <hi@alyssa.is>

#include <stdint.h>

#include <net/if.h>

struct ch_device;
struct vm_name;

struct net_config {
	int fd;
	char id[IFNAMSIZ];
	uint8_t mac[6];
};

[[gnu::nonnull]]
int ch_add_net(const struct vm_name *, const struct net_config[static 1]);

[[gnu::nonnull]]
int ch_remove_device(const struct vm_name *, const char device_id[static 1]);
