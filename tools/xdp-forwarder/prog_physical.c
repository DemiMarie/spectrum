// SPDX-License-Identifier: EUPL-1.2+
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

static __always_inline bool push_vlan_tag(struct xdp_md *ctx, __u16 tag)
{
	// Add extra space at the front of the packet.
	// This avoids reloading pointers or extra bounds checks later.
	if (bpf_xdp_adjust_head(ctx, -VLAN_HDR_SIZE))
		return false;

	struct tagged_ethhdr *hdr = (void *)(long)ctx->data;
	if (hdr + 1 > (void *)(long)ctx->data_end)
		return false;

	// Move the MAC addresses.
	__builtin_memmove(hdr, (char *)hdr + VLAN_HDR_SIZE, MAC_ADDRESS_COMBINED_SIZE);

	// Set the VLAN ID and the Ethertype of the frame.
	hdr->h_vlan_TCI = bpf_htons((__u16)tag);
	hdr->h_proto = VLAN_ETHTYPE;
	return true;
}

SEC("xdp")
int physical(struct xdp_md *ctx)
{
	__u32 ingress_ifindex = ctx->ingress_ifindex;

	if (!vlan_tag_is_valid(ingress_ifindex))
		return XDP_DROP;

	if (!push_vlan_tag(ctx, (__u16)ingress_ifindex))
		return XDP_DROP;

	// Redirect to the router interface.
	return bpf_redirect_map(&router_iface, 0, 0);
}
