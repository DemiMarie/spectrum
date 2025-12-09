// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>
// SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

pub(crate) mod packet;
pub(crate) mod protocol;
mod router;
mod upstream;

use packet::*;
use router::{InterfaceId, Router};
use upstream::Upstream;

use anyhow::bail;
use futures_util::{SinkExt, TryStreamExt};
use listenfd::ListenFd;
use log::{error, info};
use tokio::net::UnixListener;
use vhost_device_net::{IncomingPacket, VhostDeviceNet};
use vm_memory::GuestMemoryMmap;

fn main() -> anyhow::Result<()> {
    env_logger::init();

    run_router()
}
#[tokio::main(flavor = "current_thread")]
async fn run_router() -> anyhow::Result<()> {
    let mut listenfd = ListenFd::from_env();

    let Some(driver_listener) = listenfd.take_unix_listener(0)? else {
        bail!("not activated with driver socket");
    };
    let Some(app_listener) = listenfd.take_unix_listener(1)? else {
        bail!("not activated with app socket");
    };

    driver_listener.set_nonblocking(true)?;
    app_listener.set_nonblocking(true)?;

    let driver_listener = UnixListener::from_std(driver_listener)?;
    let app_listener = UnixListener::from_std(app_listener)?;

    let mut router = Router::<GuestMemoryMmap>::new(InterfaceId::Upstream);

    let (mut upstream, upstream_tx, upstream_rx) = Upstream::new(driver_listener);
    router.add_iface(InterfaceId::Upstream, upstream_tx, upstream_rx);

    tokio::spawn(async move { upstream.run().await });

    let mut app_num = 0;

    loop {
        tokio::select! {
            app_conn = app_listener.accept() => {
                info!("app connected");
                match app_conn {
                    Ok((stream, _addr)) => {
                        let device = VhostDeviceNet::from_unix_stream(stream).await?;
                        let stream = Box::pin(device.tx().await?.map_ok(|buf| Packet::Incoming { buf: Some(buf), decap_vlan: false }));
                        let sink = Box::pin(device.rx().await?.with(|packet: Packet<IncomingPacket<GuestMemoryMmap>>| async move { Ok(packet.out(None)?.into_reader()) }));
                        router.add_iface(InterfaceId::App(app_num), stream, sink);
                        app_num = app_num.checked_add(1).unwrap();
                    }
                    Err(e) => error!("app connection failed: {}", e),
                }
            }
            _ = router.run() => {}
        }
    }
}
