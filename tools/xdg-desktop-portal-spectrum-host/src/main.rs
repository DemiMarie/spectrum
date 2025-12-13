// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2024 Alyssa Ross <hi@alyssa.is>

mod documents;
mod file_chooser;

use std::cmp::max;
use std::env::args_os;
use std::ffi::OsString;
use std::io::{self, ErrorKind};
use std::os::unix::net::{UnixListener, UnixStream};
use std::os::unix::prelude::*;
use std::path::PathBuf;
use std::process::exit;
use std::slice;
use std::sync::OnceLock;

use async_executor::StaticExecutor;
use async_io::Async;
use futures_lite::prelude::*;
use futures_lite::stream::StreamExt;
use zbus::{AuthMechanism, Connection, MessageStream, connection};

use file_chooser::FileChooser;

static EXECUTOR: StaticExecutor = StaticExecutor::new();
static VSOCK_UNIX_PATH: OnceLock<PathBuf> = OnceLock::new();

async fn receive_u32(conn: &mut Async<UnixStream>) -> io::Result<u32> {
    let mut buf = [0; 4];
    conn.read_exact(&mut buf).await?;
    Ok(u32::from_be_bytes(buf))
}

async fn receive_bytestring(conn: &mut Async<UnixStream>) -> Result<Vec<u8>, String> {
    let len = receive_u32(conn)
        .await
        .map_err(|e| format!("reading length: {e}"))?;
    let mut buf = vec![0; len.try_into().unwrap()];
    conn.read_exact(&mut buf)
        .await
        .map_err(|e| format!("reading contents: {e}"))?;
    Ok(buf)
}

async fn negotiate_version(conn: &mut Async<UnixStream>) -> Result<(), String> {
    let mut num_versions = 0;
    conn.read_exact(slice::from_mut(&mut num_versions))
        .await
        .map_err(|e| format!("reading number of versions supported by client: {e}"))?;

    let mut client_versions = vec![0; num_versions.into()];
    conn.read_exact(&mut client_versions)
        .await
        .map_err(|e| format!("reading versions supported by client: {e}"))?;

    if !client_versions.contains(&1) {
        let msg = format!(
            "no supported protocol versions offered by client: {:?}",
            client_versions
        );
        return Err(msg);
    }

    conn.write_all(&[1])
        .await
        .map_err(|e| format!("communicating chosen protocol version to client: {e}"))?;

    Ok(())
}

async fn connect_to_guest(port: u32) -> Result<Async<UnixStream>, String> {
    let vsock_unix_path = VSOCK_UNIX_PATH.get().unwrap();
    let mut vsock = Async::<UnixStream>::connect(vsock_unix_path)
        .await
        .map_err(|e| format!("connecting to {:?}: {e}", vsock_unix_path))?;
    for part in [b"CONNECT ", port.to_string().as_bytes(), b"\n"] {
        vsock
            .write_all(part)
            .await
            .map_err(|e| format!("writing to VSOCK UNIX socket: {e}"))?;
    }

    // XXX: this could use UnixStream::peek if stabilized to avoid
    // reading one byte at a time.
    // https://github.com/rust-lang/rust/issues/76923
    let mut response = [0; 14]; // Length of "OK [u32::MAX]\n" is 14.
    let min_response_len = "OK 0\n".len();
    let mut response_len = 0usize;

    while response_len.checked_sub(1).and_then(|i| response.get(i)) != Some(&b'\n')
        && response_len < response.len()
    {
        let min_remaining = min_response_len.saturating_sub(response_len);
        let end = max(min_remaining, response_len + 1);
        let dest = response.get_mut(response_len..end).unwrap();
        response_len += dest.len();
        vsock
            .read_exact(dest)
            .await
            .map_err(|e| format!("reading VSOCK connection response: {e}"))?;
    }

    if !response.starts_with(b"OK ") {
        return Err(format!(
            "unexpected response from Cloud Hypervisor VSOCK handshake: {:#x?}",
            response
        ));
    }

    Ok(vsock)
}

async fn run_guest_connection(mut conn: Async<UnixStream>) -> Result<(), String> {
    negotiate_version(&mut conn).await?;
    let port = receive_u32(&mut conn)
        .await
        .map_err(|e| format!("receiving port: {e}"))?;
    let guest_share_root = receive_bytestring(&mut conn)
        .await
        .map_err(|e| format!("receiving guest share root: {e}"))?;
    let guest_share_root = PathBuf::from(OsString::from_vec(guest_share_root));

    // Collect and defer any errors, so we can inform the guest before returning and
    // closing the connection.
    let guest_dbus_conn_result = async {
        // Needs to be absolute so we can construct a file:// URL.
        if guest_share_root.is_relative() {
            return Err(format!(
                "guest provided a non-absolute share root: {:?}",
                guest_share_root
            ));
        }

        let vsock = connect_to_guest(port).await?;

        let imp = FileChooser::new(guest_share_root);
        connection::Builder::socket(vsock)
            .auth_mechanism(AuthMechanism::Anonymous)
            .name("org.freedesktop.impl.portal.desktop.spectrum")
            .unwrap()
            .serve_at("/org/freedesktop/portal/desktop", imp)
            .unwrap()
            .build()
            .await
            .map_err(|e| format!("setting up connection to guest bus: {e}"))
    }
    .await;

    if let Err(e) = conn
        .write_all(&[u8::from(guest_dbus_conn_result.is_err())])
        .await
    {
        let e = format!("sending setup response to guest: {e}");
        if guest_dbus_conn_result.is_err() {
            msg(&e);
        } else {
            return Err(e);
        }
    }

    drop(conn);
    let guest_dbus_conn = guest_dbus_conn_result?;

    msg("Created org.freedesktop.impl.portal.desktop.spectrum.host on guest bus");

    let mut guest_messages = MessageStream::from(guest_dbus_conn);
    loop {
        match guest_messages.try_next().await {
            Ok(_) => (),
            Err(zbus::Error::InputOutput(e)) if e.kind() == ErrorKind::BrokenPipe => break Ok(()),
            Err(e) => return Err(format!("communicating with guest bus: {e}")),
        }
    }
}

/// Given a listener for guest-to-host connections, find the path of
/// the listening socket for host-to-guest connections.
fn listening_vsock_path(connection: &UnixListener) -> Result<PathBuf, String> {
    let mut listening_addr = connection
        .local_addr()
        .map_err(|e| format!("getsockname(fd={}): {e}", connection.as_raw_fd()))?
        .as_pathname()
        .ok_or_else(|| format!("fd {} is not listening on a path", connection.as_raw_fd()))?
        .as_os_str()
        .to_os_string()
        .into_vec();

    let mut i = listening_addr.len() - 1;

    loop {
        match (i != 0).then_some(listening_addr[i]) {
            Some(b'0'..=b'9') => {
                i -= 1;
            }
            Some(b'_') => {
                break;
            }
            _ => {
                let os_string = OsString::from_vec(listening_addr);
                let msg = format!("can't infer listening VSOCK path from {:?}", os_string);
                return Err(msg);
            }
        }
    }

    listening_addr.truncate(i);
    Ok(OsString::from_vec(listening_addr).into())
}

fn read_argv() {
    let mut args = args_os();
    args.next();

    if args.next().is_some() {
        msg("too many arguments");
        exit(1);
    }
}

fn run() -> Result<(), String> {
    read_argv();

    async_io::block_on(EXECUTOR.run(async {
        // SAFETY: safe because we won't use fd 0 anywhere else.
        let stdin = Async::new(unsafe { UnixListener::from_raw_fd(0) })
            .map_err(|e| format!("listening on stdin: {e}"))?;

        VSOCK_UNIX_PATH
            .set(listening_vsock_path(stdin.get_ref())?)
            .unwrap();

        let mut initialized = false;

        loop {
            let (conn, _) = match stdin.accept().await {
                Ok(conn) => conn,
                Err(e) => {
                    msg(&format!("accepting connection from guest: {e}"));
                    continue;
                }
            };

            if !initialized {
                let session = Connection::session()
                    .await
                    .map_err(|e| format!("connecting to session bus: {e}"))?;
                documents::init(&session).await;
                file_chooser::init(&session).await;
                initialized = true;
            }

            EXECUTOR
                .spawn(async move {
                    if let Err(e) = run_guest_connection(conn).await {
                        msg(&format!("guest connection error: {e}"));
                    }
                })
                .detach();
        }
    }))
}

fn msg(e: &str) {
    if let Some(prog) = args_os().next()
        && let Some(prog) = PathBuf::from(prog).file_name()
    {
        eprint!("{}: ", prog.to_string_lossy());
    }
    eprintln!("{e}");
}

fn main() {
    if let Err(e) = run() {
        msg(&e);
        exit(1);
    }
}
