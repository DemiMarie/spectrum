// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>

#include <stdio.h>
#include <stdlib.h>
#include <net/if.h>
#include <bpf/bpf.h>
#include <err.h>

int main(int argc, char **argv)
{
	if (argc < 2)
		err(EXIT_FAILURE, "missing interface name");

	int router_idx = if_nametoindex(argv[1]);
	if (router_idx <= 0)
		err(EXIT_FAILURE, "error getting router interface");

	int map_fd = bpf_obj_get("/sys/fs/bpf/router_iface");
	if (map_fd < 0)
		err(EXIT_FAILURE, "failed to open bpf map");

	int id = 0;
	if (bpf_map_update_elem(map_fd, &id, &router_idx, 0) < 0)
		err(EXIT_FAILURE, "failed to update bpf map");
}
