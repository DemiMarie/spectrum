// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>

use std::io::{self, Cursor, Read};
use std::pin::Pin;
use std::time::{Duration, Instant};

use crate::packet::*;
use crate::protocol::*;
use crate::router::{PacketSink, PacketStream};

use futures_util::{Sink, SinkExt, Stream, StreamExt};
use log::{debug, error, info, warn};
use tokio::net::UnixListener;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tokio_util::sync::PollSender;
use vhost_device_net::{IncomingPacket, VhostDeviceNet};
use vm_memory::GuestMemoryMmap;
use zerocopy::FromBytes;

pub struct Upstream {
    driver_listener: UnixListener,
    active_interface: Option<u16>,
    reevaluate_active_interface: Pin<Box<tokio::time::Sleep>>,
    radv_valid_until: Vec<(u16, Instant)>,
    tx_sender: mpsc::Sender<Packet<IncomingPacket<GuestMemoryMmap>>>,
    rx_receiver: mpsc::Receiver<Packet<IncomingPacket<GuestMemoryMmap>>>,
}

impl Upstream {
    pub fn new(
        driver_listener: UnixListener,
    ) -> (
        Upstream,
        PacketStream<GuestMemoryMmap>,
        PacketSink<GuestMemoryMmap>,
    ) {
        let (tx_sender, tx_receiver) = mpsc::channel(64);
        let (rx_sender, rx_receiver) = mpsc::channel(64);

        (
            Upstream {
                driver_listener,
                active_interface: None,
                reevaluate_active_interface: Box::pin(tokio::time::sleep(Duration::from_hours(
                    24 * 365,
                ))),
                radv_valid_until: Default::default(),
                tx_sender,
                rx_receiver,
            },
            Box::pin(ReceiverStream::new(tx_receiver).map(Ok)),
            Box::pin(
                PollSender::new(rx_sender)
                    .sink_map_err(|_| io::Error::other("driver rx channel closed")),
            ),
        )
    }
    pub async fn run(&mut self) -> io::Result<()> {
        let mut device_tx: Option<Pin<Box<dyn Stream<Item = _> + Send>>> = None;
        let mut device_rx: Option<Pin<Box<dyn Sink<_, Error = _> + Send>>> = None;
        loop {
            tokio::select! {
                driver_conn = self.driver_listener.accept() => {
                    info!("driver connected");
                    match driver_conn {
                        Ok((stream, _addr)) => {
                            self.radv_valid_until.clear();
                            self.active_interface = None;
                            self.reevaluate_active_interface.as_mut().reset((Instant::now() + Duration::from_hours(24 * 365)).into());

                            let device = VhostDeviceNet::from_unix_stream(stream).await?;
                            device_tx = Some(Box::pin(device.tx().await?));
                            device_rx = Some(Box::pin(device.rx().await?));
                        }
                        Err(e) => error!("driver connection failed: {}", e),
                    }
                }
                tx_res = async { device_tx.as_mut().unwrap().next().await }, if device_tx.is_some() => {
                    let Some(Ok(buf)) = tx_res else {
                        info!("driver tx err");
                        continue;
                    };

                    let mut packet = Packet::Incoming { buf: Some(buf), decap_vlan: true };
                    let PacketHeaders { ether_frame, vlan_tag: vlan_in, ipv6_hdr, peek_slice, buf, .. } = packet.headers()?;

                    let Some(vlan_tag) = vlan_in else {
                        warn!("untagged packet from driver");
                        continue;
                    };

                    let vlan_id = u16::from(vlan_tag.tag_control_information) & 0xfff;

                    if let Some(ref ipv6_hdr) = ipv6_hdr && ipv6_hdr.next_header == IP_PROTO_ICMP6 {
                        let (icmpv6_hdr, icmpv6_data) = Icmpv6Header::ref_from_prefix(peek_slice).map_err(|_| io::Error::other("short icmpv6 header"))?;

                        if icmpv6_hdr.msg_type == ICMP6_TYPE_R_ADV {
                            let data = Cursor::new(icmpv6_data).chain(Cursor::new(buf.full_packet()));
                            let r_adv = Icmpv6RouterAdvertisement::read_from_io(data)?;
                            if r_adv.router_lifetime != 0 {
                                let now = Instant::now();
                                let r_adv_timeout = now + Duration::from_secs(u16::from(r_adv.router_lifetime).into());
                                match self.radv_valid_until.binary_search_by_key(&vlan_id, |&(if_idx, _)| if_idx) {
                                    Ok(pos) => self.radv_valid_until[pos] = (vlan_id, r_adv_timeout),
                                    Err(insert_pos) => self.radv_valid_until.insert(insert_pos, (vlan_id, r_adv_timeout)),
                                };
                                debug!("router advertisement received on interface {}: {:x?} {:x?} {:?}", vlan_id, ether_frame, ipv6_hdr, r_adv);

                                let prev_active_interface = self.active_interface.unwrap_or(u16::MAX);
                                if vlan_id < prev_active_interface || self.reevaluate_active_interface.deadline() < now.into() {
                                    self.active_interface = Some(vlan_id);
                                    info!("set active interface to {}", vlan_id);
                                    self.reevaluate_active_interface.as_mut().reset(r_adv_timeout.into());
                                } else if vlan_id == prev_active_interface {
                                    self.reevaluate_active_interface.as_mut().reset(r_adv_timeout.into());
                                }
                            }
                        }
                    }

                    if Some(vlan_id) != self.active_interface {
                        debug!("dropping packet from inactive interface {}", vlan_id);
                        continue;
                    }

                    self.tx_sender.send(packet).await.map_err(io::Error::other)?;
                }
                rx_res = self.rx_receiver.recv() => {
                    let Some(packet) = rx_res else {
                        info!("driver rx err");
                        continue;
                    };

                    let Some(sink) = device_rx.as_mut() else {
                        warn!("dropped packet because driver is not ready");
                        continue;
                    };

                    let Some(active_interface) = &self.active_interface else {
                        warn!("dropped packet because active interface is unknown");
                        continue;
                    };

                    // Add active interface vlan
                    let vlan_out = VlanTag {
                        ether_type: ETHER_TYPE_802_1Q.into(),
                        tag_control_information: (*active_interface).into(),
                    };

                    let packet = packet.out(Some(vlan_out))?;

                    match tokio::time::timeout(Duration::from_secs(1), sink.send(packet.into_reader())).await {
                        Err(_) => warn!("driver rx has been blocked for 1 sec, dropping packet"),
                        Ok(Err(e)) => return Err(e),
                        Ok(Ok(())) => {},
                    }
                }
                () = &mut self.reevaluate_active_interface => {
                    let now = Instant::now();
                    let prev_active_interface = self.active_interface.unwrap_or(u16::MAX);
                    info!("router advertisement expired on interface {}", prev_active_interface);
                    if let Some((if_idx, valid_until)) = self.radv_valid_until.iter().find(|(_, valid_until)| *valid_until > now) {
                        self.active_interface = Some(*if_idx);
                        info!("set active interface to {}", if_idx);
                        self.reevaluate_active_interface.as_mut().reset((*valid_until).into());
                    } else {
                        self.reevaluate_active_interface.as_mut().reset((now + Duration::from_hours(24 * 365)).into());
                    }
                }
            }
        }
    }
}
