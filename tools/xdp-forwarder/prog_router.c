// SPDX-License-Identifier: EUPL-1.2+ AND (GPL-2.0-or-later OR BSD-2-Clause)
// SPDX-FileCopyrightText: 2021 The xdp-tutorial Authors
// SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>
// SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

#include "helpers.h"

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

static __always_inline bool vlan_tag_pop(struct xdp_md *ctx, __u16 *tag)
{
	struct maybe_tagged_ethhdr *hdr = (void *)(long)ctx->data;
	if (hdr + 1 > (void *)(long)ctx->data_end)
		return false;

	// 0x8A88 is also valid but the router does not
	// use it.  It's meant for service provider VLANs.
	if (hdr->tagged.eth.h_proto != bpf_htons(VLAN_ETHTYPE))
		return false;

	*tag = bpf_ntohs(hdr->tagged.vlan.h_vlan_TCI);

	// Move the MAC addresses.
	// Ethertype is already in correct position.
	__builtin_memmove(&hdr->untagged.eth.mac_addresses,
	                  &hdr->tagged.eth.mac_addresses,
	                  sizeof(hdr->tagged.eth.mac_addresses));

	// Move the head pointer to the new Ethernet header.
	// Doing this last avoids needing to reload pointers
	// and add extra bounds checks earlier.
	return !bpf_xdp_adjust_head(ctx, (int)sizeof(hdr->untagged.pad));
}

SEC("xdp")
int router(struct xdp_md *ctx)
{
	__u16 vlid;

	if (!vlan_tag_pop(ctx, &vlid))
		return XDP_DROP;

	if (!vlan_tag_is_valid(vlid))
		return XDP_DROP;

	// Redirect to the correct physical interface.
	return bpf_redirect(vlid, 0);
}
