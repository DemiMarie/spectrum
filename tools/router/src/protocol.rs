// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>

use zerocopy::byteorder::network_endian::{U16, U32};
use zerocopy::*;

pub const ETHER_TYPE_IPV6: u16 = 0x86dd;
pub const ETHER_TYPE_802_1Q: u16 = 0x8100;
pub const IP_PROTO_ICMP6: u8 = 0x3a;
pub const ICMP6_TYPE_R_ADV: u8 = 134;

pub type MacAddr = [u8; 6];
pub fn is_multicast(mac: &MacAddr) -> bool {
    match mac {
        [0xff, 0xff, 0xff, 0xff, 0xff, 0xff] => true,
        [0x01, 0x80, 0xc2, _, _, _] => true, // 802 group
        [0x33, 0x33, _, _, _, _] => true,    // IPv6 multicast
        _ => false,
    }
}

#[derive(Debug, PartialEq, Eq, FromBytes, IntoBytes, KnownLayout, Immutable, Unaligned)]
#[repr(C)]
pub struct EtherFrame {
    pub dst_addr: MacAddr,
    pub src_addr: MacAddr,
}

pub type EtherType = U16;

#[derive(Debug, PartialEq, Eq, FromBytes, IntoBytes, KnownLayout, Immutable, Unaligned)]
#[repr(C)]
pub struct VlanTag {
    pub ether_type: U16,
    pub tag_control_information: U16,
}

#[derive(Debug, PartialEq, Eq, FromBytes, IntoBytes, KnownLayout, Immutable, Unaligned)]
#[repr(C)]
pub struct Ipv6Header {
    pub version_traffic_class_flow_label: U32,
    pub payload_length: U16,
    pub next_header: u8,
    pub hop_limit: u8,
    pub src_addr: [u8; 16],
    pub dst_addr: [u8; 16],
}

#[derive(Debug, PartialEq, Eq, FromBytes, IntoBytes, KnownLayout, Immutable, Unaligned)]
#[repr(C)]
pub struct Icmpv6Header {
    pub msg_type: u8,
    pub code: u8,
    pub checksum: U16,
}

#[derive(Debug, PartialEq, Eq, FromBytes, IntoBytes, KnownLayout, Immutable, Unaligned)]
#[repr(C)]
pub struct Icmpv6RouterAdvertisement {
    pub hop_limit: u8,
    pub flags: u8,
    pub router_lifetime: U16,
    pub reachable_time: U32,
    pub retrans_timer: U32,
}
