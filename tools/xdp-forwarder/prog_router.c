// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>

#define VLAN_MAX_DEPTH 1

#include <linux/bpf.h>
#include <bpf/bpf_endian.h>
#include "parsing_helpers.h"
#include "rewrite_helpers.h"

// The map is actually not used by this program, but just included
// to keep the reference-counted pin alive before any physical interfaces
// are added.
struct {
	__uint(type, BPF_MAP_TYPE_DEVMAP);
	__type(key, int);
	__type(value, int);
	__uint(max_entries, 1);
	__uint(pinning, LIBBPF_PIN_BY_NAME);
} router_iface SEC(".maps");


SEC("xdp")
int router(struct xdp_md *ctx)
{
	void *data_end = (void *)(long)ctx->data_end;
	void *data = (void *)(long)ctx->data;

	struct hdr_cursor nh;
	nh.pos = data;

	struct ethhdr *eth;
	if (parse_ethhdr(&nh, data_end, &eth) < 0)
		return XDP_DROP;

	int vlid = vlan_tag_pop(ctx, eth);
	if (vlid < 0)
		return XDP_DROP;

	return bpf_redirect(vlid, 0);
}
