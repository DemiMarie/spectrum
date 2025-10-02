/* SPDX-License-Identifier: (GPL-2.0-or-later OR BSD-2-Clause) */
/* SPDX-FileCopyrightText: 2021 The xdp-tutorial Authors */
// SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>
// SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
/*
 * This file contains parsing functions that are used in the XDP programs.
 * They handle the following:
 *
 * - Validating VLAN tags.
 * - Extracting Ethernet and VLAN headers.
 * - Moving the head of an XDP context by the size of a VLAN header.
 * - Moving the Ethernet source and destination MAC addresses by the
 *   size of a VLAN header.
 */

#ifndef HELPERS_H
#define HELPERS_H

#include <linux/bpf.h>
#include <bpf/bpf_endian.h>
#include <bpf/bpf_helpers.h>

#define VLAN_HDR_SIZE 4
#define MAC_ADDRESS_COMBINED_SIZE 12
#define VLAN_VID_MASK           0x0fff /* VLAN Identifier */
#define VLAN_ETHTYPE (bpf_htons(0x8100))

struct tagged_ethhdr {
	__u8 mac_addresses[MAC_ADDRESS_COMBINED_SIZE];
	__be16 h_proto;
	__be16 h_vlan_TCI;
	__be16 h_vlan_encapsulated_proto;
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
