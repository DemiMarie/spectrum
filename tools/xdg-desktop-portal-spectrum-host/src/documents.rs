// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2024 Alyssa Ross <hi@alyssa.is>

use std::ffi::OsString;
use std::os::unix::prelude::*;
use std::path::PathBuf;
use std::sync::OnceLock;

use rustix::fs::{Mode, OFlags, open};
use zbus::{Connection, proxy};

const DOCUMENT_ADD_FLAGS_REUSE_EXISTING: u32 = 1 << 0;

static PROXY: OnceLock<DocumentsProxy> = OnceLock::new();

#[proxy(
    assume_defaults = true,
    default_path = "/org/freedesktop/portal/documents",
    interface = "org.freedesktop.portal.Documents"
)]
trait Documents {
    #[allow(clippy::too_many_arguments)]
    fn add_named_full(
        &self,
        o_path_fd: zbus::zvariant::Fd<'_>,
        filename: &[u8],
        flags: u32,
        app_id: &str,
        permissions: &[&str],
    ) -> zbus::Result<(
        String,
        std::collections::HashMap<String, zbus::zvariant::OwnedValue>,
    )>;
}

pub async fn init(conn: &Connection) {
    PROXY.set(DocumentsProxy::new(conn).await.unwrap()).unwrap();
}

pub async fn share_file(source_path: PathBuf, writable: bool) -> Result<PathBuf, String> {
    // TODO: implement this.
    if source_path.exists() && !source_path.is_file() {
        return Err("only regular files can currently be shared".to_string());
    }

    // This might not be safe to unwrap any more once we support sharing directories.
    let parent = source_path.parent().unwrap();

    let flags = OFlags::CLOEXEC | OFlags::DIRECTORY | OFlags::PATH;
    let fd = open(parent, flags, Mode::empty())
        .map_err(|e| format!("opening {:?} O_PATH: {e}", parent))?;

    let mut basename = source_path.file_name().unwrap().as_bytes().to_vec();
    basename.push(0);

    let perms = if writable {
        &["read", "write", "grant-permissions"][..]
    } else {
        &["read", "grant-permissions"][..]
    };

    let (doc_id, _) = PROXY
        .get()
        .unwrap()
        .add_named_full(
            fd.into(),
            &basename,
            DOCUMENT_ADD_FLAGS_REUSE_EXISTING,
            "",
            perms,
        )
        .await
        .map_err(|e| format!("AddNamedFull: {e}"))?;

    basename.pop();
    let basename = OsString::from_vec(basename);

    let mut r = PathBuf::from("doc");
    r.push(doc_id);
    r.push(basename);
    Ok(r)
}
