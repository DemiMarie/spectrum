// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022 Alyssa Ross <hi@alyssa.is>

#include <net/if.h>

int tap_open(char name[static IFNAMSIZ], int flags);
