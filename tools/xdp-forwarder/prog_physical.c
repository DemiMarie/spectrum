// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>

#define VLAN_MAX_DEPTH 1

#include <linux/bpf.h>
#include <bpf/bpf_endian.h>
#include "parsing_helpers.h"
#include "rewrite_helpers.h"

struct {
	__uint(type, BPF_MAP_TYPE_DEVMAP);
	__type(key, int);
	__type(value, int);
	__uint(max_entries, 1);
	__uint(pinning, LIBBPF_PIN_BY_NAME);
} router_iface SEC(".maps");

SEC("xdp")
int physical(struct xdp_md *ctx)
{
	void *data_end = (void *)(long)ctx->data_end;
	void *data = (void *)(long)ctx->data;

	struct hdr_cursor nh;
	nh.pos = data;

	struct ethhdr *eth;
	if (parse_ethhdr(&nh, data_end, &eth) < 0)
		return XDP_DROP;

	if (ctx->ingress_ifindex < 1 || ctx->ingress_ifindex > VLAN_VID_MASK)
		return XDP_DROP;

	if (vlan_tag_push(ctx, eth, ctx->ingress_ifindex) < 0)
		return XDP_DROP;

	return bpf_redirect_map(&router_iface, 0, 0);
}
