// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>

use std::io::{self, Chain, Cursor, Read};

use crate::protocol::*;

use arrayvec::ArrayVec;
use zerocopy::*;

pub enum PacketData<R> {
    Incoming(R),
    Bytes(Cursor<Box<[u8]>>),
}

impl<R: Read> Read for PacketData<R> {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        match self {
            PacketData::Incoming(r) => r.read(buf),
            PacketData::Bytes(b) => b.read(buf),
        }
    }
}

impl<R: Read> PacketData<R> {
    pub fn full_packet(&mut self) -> &[u8] {
        match self {
            PacketData::Bytes(b) => b.get_ref().as_ref(),
            PacketData::Incoming(r) => {
                let mut buf = vec![];
                r.read_to_end(&mut buf).unwrap();
                *self = PacketData::Bytes(Cursor::new(buf.into_boxed_slice()));
                let PacketData::Bytes(b) = self else {
                    unreachable!()
                };
                b.get_ref().as_ref()
            }
        }
    }
}

pub enum Packet<R> {
    /// The packet has not been looked at / read into our memory yet
    Incoming { decap_vlan: bool, buf: Option<R> },
    /// We've read the head of the packet to look at the headers.
    Peek {
        decap_vlan: bool,
        peek: ArrayVec<u8, 64>,
        buf: PacketData<R>,
    },
}

pub struct PacketHeaders<'a, R> {
    pub ether_frame: &'a mut EtherFrame,
    pub vlan_tag: Option<&'a mut VlanTag>,
    pub ether_type: &'a mut EtherType,
    pub ipv6_hdr: Option<&'a mut Ipv6Header>,
    pub peek_slice: &'a mut [u8],
    pub buf: &'a mut PacketData<R>,
}

impl<R: Read> Packet<R> {
    fn peek(
        &mut self,
    ) -> (
        &mut ArrayVec<u8, 64>,
        &mut PacketData<R>,
        &mut bool, // decap_vlan
    ) {
        match self {
            Packet::Incoming { buf, decap_vlan } => {
                let mut buf = std::mem::take(buf).unwrap();
                // A stack allocation which can keep all headers we are interested in
                let mut peek = [0u8; 64];
                // Read the first 64 bytes
                // 64 >= 14 (ether) + 4 (vlan) + 40 (ipv6) + 4 (icmpv6)
                let n = buf.read(&mut peek).unwrap();

                let buf = PacketData::Incoming(buf);
                let mut peek = ArrayVec::from(peek);
                peek.truncate(n);
                *self = Packet::Peek {
                    peek,
                    buf,
                    decap_vlan: *decap_vlan,
                };
                let Packet::Peek {
                    peek,
                    buf,
                    decap_vlan,
                } = self
                else {
                    unreachable!()
                };
                (peek, buf, decap_vlan)
            }
            Packet::Peek {
                peek,
                buf,
                decap_vlan,
            } => (peek, buf, decap_vlan),
        }
    }
    pub fn headers(&mut self) -> io::Result<PacketHeaders<'_, R>> {
        let (peek, buf, decap_vlan) = self.peek();
        let peek_slice = peek.as_mut_slice();
        let (ether_frame, peek_slice) = EtherFrame::mut_from_prefix(peek_slice)
            .map_err(|_| io::Error::other("packet with <12 bytes"))?;
        let (ether_type, _) = EtherType::ref_from_prefix(peek_slice)
            .map_err(|_| io::Error::other("packet with <14 bytes"))?;

        let (vlan_tag, peek_slice) = if *decap_vlan && *ether_type == ETHER_TYPE_802_1Q {
            let (vlan, peek_slice) = VlanTag::mut_from_prefix(peek_slice)
                .map_err(|_| io::Error::other("packet with <16 bytes"))?;
            (Some(vlan), peek_slice)
        } else {
            (None, peek_slice)
        };
        let (ether_type, peek_slice) = EtherType::mut_from_prefix(peek_slice)
            .map_err(|_| io::Error::other("packet with <18 bytes"))?;

        let (ipv6_hdr, peek_slice) = if *ether_type == ETHER_TYPE_IPV6 {
            let (ipv6_hdr, peek_slice) = Ipv6Header::mut_from_prefix(peek_slice)
                .map_err(|_| io::Error::other("short ipv6 header"))?;
            (Some(ipv6_hdr), peek_slice)
        } else {
            (None, peek_slice)
        };

        Ok(PacketHeaders {
            ether_frame,
            vlan_tag,
            ether_type,
            ipv6_hdr,
            peek_slice,
            buf,
        })
    }
    pub fn out(mut self, vlan_encap: Option<VlanTag>) -> io::Result<OutgoingPacket<R>> {
        let PacketHeaders {
            ether_frame,
            ether_type,
            ipv6_hdr,
            peek_slice,
            ..
        } = self.headers()?;

        let mut headers_out = ArrayVec::<u8, 128>::new();
        headers_out
            .try_extend_from_slice(ether_frame.as_bytes())
            .unwrap();
        if let Some(vlan_tag) = vlan_encap {
            headers_out
                .try_extend_from_slice(vlan_tag.as_bytes())
                .unwrap();
        }
        headers_out
            .try_extend_from_slice(ether_type.as_bytes())
            .unwrap();
        if let Some(ipv6_hdr) = ipv6_hdr {
            headers_out
                .try_extend_from_slice(ipv6_hdr.as_bytes())
                .unwrap();
        }
        headers_out.try_extend_from_slice(peek_slice).unwrap();

        let Packet::Peek {
            peek: _peek, buf, ..
        } = self
        else {
            unreachable!()
        };
        Ok(OutgoingPacket { headers_out, buf })
    }
}

pub struct OutgoingPacket<R> {
    /// This has extra space for added encapsulation / VLAN tags
    headers_out: ArrayVec<u8, 128>,
    buf: PacketData<R>,
}

impl<R: Read> OutgoingPacket<R> {
    pub fn into_reader(self) -> Chain<Cursor<ArrayVec<u8, 128>>, PacketData<R>> {
        Cursor::new(self.headers_out).chain(self.buf)
    }
}
