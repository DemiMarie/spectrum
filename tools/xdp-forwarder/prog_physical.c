// SPDX-License-Identifier: EUPL-1.2+ AND (GPL-2.0-or-later OR BSD-2-Clause)
// SPDX-FileCopyrightText: 2021 The xdp-tutorial Authors
// SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>
// SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

#include "helpers.h"

struct {
	__uint(type, BPF_MAP_TYPE_DEVMAP);
	__type(key, int);
	__type(value, int);
	__uint(max_entries, 1);
	__uint(pinning, LIBBPF_PIN_BY_NAME);
} router_iface SEC(".maps");

static __always_inline bool vlan_tag_push(struct xdp_md *ctx, __u16 tag)
{
	struct maybe_tagged_ethhdr *hdr;

	// Add extra space at the front of the packet.
	// Doing this first avoids reloading pointers and
	// extra bounds checks later.
	if (bpf_xdp_adjust_head(ctx, -(int)sizeof(hdr->untagged.pad)))
		return false;

	hdr = (void *)(long)ctx->data;
	if (hdr + 1 > (void *)(long)ctx->data_end)
		return false;

	// Move the MAC addresses.
	// Ethertype is already in the correct position.
	__builtin_memmove(&hdr->tagged.eth.mac_addresses,
	                  &hdr->untagged.eth.mac_addresses,
	                  sizeof(hdr->tagged.eth.mac_addresses));

	// Set the VLAN ID and the Ethertype of the frame.
	hdr->tagged.vlan.h_vlan_TCI = bpf_htons((__u16)tag);
	hdr->tagged.eth.h_proto = bpf_htons(VLAN_ETHTYPE);
	return true;
}

SEC("xdp")
int physical(struct xdp_md *ctx)
{
	__u32 ingress_ifindex = ctx->ingress_ifindex;

	if (!vlan_tag_is_valid(ingress_ifindex))
		return XDP_DROP;

	if (!vlan_tag_push(ctx, (__u16)ingress_ifindex))
		return XDP_DROP;

	// Redirect to the router interface.
	return bpf_redirect_map(&router_iface, 0, 0);
}
