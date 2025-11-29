// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>

pub(crate) mod packet;
pub(crate) mod protocol;
mod router;
mod upstream;

use std::path::PathBuf;

use packet::*;
use router::{InterfaceId, Router};
use upstream::Upstream;

use clap::Parser;
use futures_util::{SinkExt, TryStreamExt};
use log::{error, info};
use tokio::net::UnixListener;
use vhost_device_net::{IncomingPacket, VhostDeviceNet};
use vm_memory::GuestMemoryMmap;

#[derive(Parser, Debug)]
#[command()] //version = None, about = None, long_about = None)]
struct Args {
    #[arg(long)]
    driver_listen_path: PathBuf,
    #[arg(long)]
    app_listen_path: PathBuf,
}

fn main() -> anyhow::Result<()> {
    env_logger::init();
    let args = Args::parse();

    for path in [&args.driver_listen_path, &args.app_listen_path] {
        let _ = std::fs::remove_file(path);
    }

    run_router(args)
}
#[tokio::main(flavor = "current_thread")]
async fn run_router(args: Args) -> anyhow::Result<()> {
    let app_listener = UnixListener::bind(&args.app_listen_path)?;
    let driver_listener = UnixListener::bind(&args.driver_listen_path)?;

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
