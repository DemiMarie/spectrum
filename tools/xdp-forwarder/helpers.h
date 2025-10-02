/* SPDX-License-Identifier: (GPL-2.0-or-later OR BSD-2-Clause) */
/* SPDX-FileCopyrightText: 2021 The xdp-tutorial Authors */
// SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>
// SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
/*
 * This file contains a helper for validating a VLAN tag,
 * as well as structs used by both BPF programs.
 */

#ifndef HELPERS_H
#define HELPERS_H

#include <linux/bpf.h>
#include <bpf/bpf_endian.h>
#include <bpf/bpf_helpers.h>

#define VLAN_ETHTYPE    0x8100 /* Ethertype for tagged frames */

struct ethhdr {
	struct {
		__u8 destination_mac[6];
		__u8 source_mac[6];
	} mac_addresses;
	__be16 h_proto;
};

struct vlan_hdr {
	__be16 h_vlan_TCI;
	__be16 h_vlan_encapsulated_proto;
};

struct maybe_tagged_ethhdr {
	union {
		struct {
			struct ethhdr eth;
			struct vlan_hdr vlan;
		} tagged;
		struct {
			struct vlan_hdr pad;
			struct ethhdr eth;
		} untagged;
	};
};

// The router doesn't support the PCP and DEI bits
// and they are not part of the VLAN tag.
// Therefore, ensure they are unset.
// Also reject VLAN 0, which is reserved.
static __always_inline bool vlan_tag_is_valid(__u32 tag)
{
	return tag >= 1 && tag <= 0x0FFF;
}

#endif /* HELPERS_H */
