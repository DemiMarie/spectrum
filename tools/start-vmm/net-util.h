// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022 Alyssa Ross <hi@alyssa.is>

#include <net/if.h>

int if_up(const char name[static 1]);
int if_down(const char name[static 1]);

int bridge_add(const char name[static 1]);
int bridge_add_if(const char brname[static 1], const char ifname[static 1]);
int bridge_delete(const char name[static 1]);

int tap_open(char name[static IFNAMSIZ], int flags);
int tap_set_persist(int fd, bool persist);
