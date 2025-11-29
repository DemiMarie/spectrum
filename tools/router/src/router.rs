// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>

use std::collections::HashMap;
use std::io::{self, Cursor};
use std::net::Ipv6Addr;
use std::pin::Pin;
use std::time::Duration;

use crate::packet::*;
use crate::protocol::*;

use futures_util::{FutureExt, Sink, SinkExt, Stream, StreamExt};
use log::{debug, info, warn};
use tokio_stream::StreamMap;
use vhost_device_net::IncomingPacket;
use vm_memory::GuestMemory;

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum InterfaceId {
    Upstream,
    App(usize),
    Broadcast,
}

pub type PacketStream<M> = Pin<Box<dyn Stream<Item = io::Result<Packet<IncomingPacket<M>>>>>>;
pub type PacketSink<M> = Pin<Box<dyn Sink<Packet<IncomingPacket<M>>, Error = io::Error>>>;

pub struct Router<M: GuestMemory> {
    streams: StreamMap<InterfaceId, PacketStream<M>>,
    sinks: HashMap<InterfaceId, PacketSink<M>>,
    fib: HashMap<Ipv6Addr, (MacAddr, InterfaceId)>,
    default_out: InterfaceId,
}

impl<M: GuestMemory> Router<M> {
    pub fn new(default_out: InterfaceId) -> Self {
        Self {
            streams: Default::default(),
            sinks: Default::default(),
            fib: Default::default(),
            default_out,
        }
    }

    pub fn add_iface(&mut self, id: InterfaceId, stream: PacketStream<M>, sink: PacketSink<M>) {
        self.streams.insert(id.clone(), stream);
        self.sinks.insert(id.clone(), sink);
    }

    pub async fn run(&mut self) -> io::Result<()> {
        loop {
            let next_res = self.streams.next().await;
            let Some((in_iface, Ok(mut packet))) = next_res else {
                info!("incoming err");
                continue;
            };

            let PacketHeaders {
                ether_frame,
                ipv6_hdr,
                ..
            } = packet.headers()?;

            let Some(ipv6_hdr) = ipv6_hdr else {
                continue;
            };
            let src_addr = Ipv6Addr::from(ipv6_hdr.src_addr);
            let dst_addr = Ipv6Addr::from(ipv6_hdr.dst_addr);

            let out_iface = if is_multicast(&ether_frame.dst_addr) {
                InterfaceId::Broadcast
            } else if let Some((dst_mac, if_idx)) = self.fib.get(&dst_addr) {
                ether_frame.dst_addr = *dst_mac;
                if_idx.clone()
            } else if in_iface != self.default_out {
                self.default_out.clone()
            } else {
                warn!("no fib match for {}, dropping packet", dst_addr);
                continue;
            };

            if in_iface != self.default_out
                && !src_addr.is_unspecified()
                && !src_addr.is_multicast()
                && !self.fib.contains_key(&src_addr)
            {
                debug!(
                    "adding fib entry for {} -> {:x?} {:?}",
                    src_addr, ether_frame.src_addr, in_iface
                );
                self.fib
                    .insert(src_addr, (ether_frame.src_addr, in_iface.clone()));
            }

            match out_iface {
                InterfaceId::Broadcast => {
                    let Packet::Peek {
                        peek,
                        mut buf,
                        decap_vlan,
                    } = packet
                    else {
                        unreachable!()
                    };
                    let buf = Box::<[u8]>::from(buf.full_packet());
                    futures_util::future::try_join_all(
                        self.sinks
                            .iter_mut()
                            .filter(|(id, _)| **id != in_iface)
                            .map(|(id, sink)| {
                                let packet = Packet::Peek {
                                    peek: peek.clone(),
                                    buf: PacketData::Bytes(Cursor::new(buf.clone())),
                                    decap_vlan,
                                };
                                let fut = sink.send(packet);
                                tokio::time::timeout(Duration::from_secs(1), fut).map(move |res| match res {
                                    Err(_) => {
                                        warn!("interface {:?} has been blocked for 1 sec, dropping packet", id);
                                        Ok(())
                                    },
                                    Ok(Err(e)) => Err(e),
                                    Ok(Ok(())) => Ok(()),
                                })
                            }),
                    )
                    .await?;
                }
                ref unicast => {
                    let Some(sink) = self.sinks.get_mut(unicast) else {
                        warn!("dropped packet because interface is not ready");
                        continue;
                    };
                    match tokio::time::timeout(Duration::from_secs(1), sink.send(packet)).await {
                        Err(_) => warn!(
                            "interface {:?} has been blocked for 1 sec, dropping packet",
                            unicast
                        ),
                        Ok(Err(e)) => return Err(e),
                        Ok(Ok(())) => {}
                    }
                }
            }
        }
    }
}
