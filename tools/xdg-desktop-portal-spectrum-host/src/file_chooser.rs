// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2024 Alyssa Ross <hi@alyssa.is>

use std::collections::BTreeMap;
use std::ffi::OsString;
use std::os::unix::prelude::*;
use std::path::PathBuf;
use std::sync::OnceLock;

use percent_encoding::percent_decode;
use url::Url;
use zbus::zvariant::{Array, ObjectPath, OwnedValue, Value};
use zbus::{Connection, interface};

use crate::documents::share_file;
use crate::msg;

const XDG_DESKTOP_PORTAL_RESPONSE_SUCCESS: u32 = 0;
const XDG_DESKTOP_PORTAL_RESPONSE_CANCELLED: u32 = 1;
const XDG_DESKTOP_PORTAL_RESPONSE_OTHER: u32 = 2;

static PROXY: OnceLock<FileChooserProxy> = OnceLock::new();

#[derive(Debug)]
pub struct FileChooser {
    guest_share_root: PathBuf,
}

#[interface(
    name = "org.freedesktop.impl.portal.FileChooser",
    proxy(
        assume_defaults = false,
        default_path = "/org/freedesktop/portal/desktop",
        default_service = "org.freedesktop.impl.portal.desktop.gtk",
    )
)]
impl FileChooser {
    async fn open_file(
        &self,
        handle: ObjectPath<'_>,
        app_id: &str,
        parent_window: &str,
        title: &str,
        options: BTreeMap<&str, Value<'_>>,
    ) -> zbus::fdo::Result<(u32, BTreeMap<String, OwnedValue>)> {
        match self
            .open_file_impl(handle, app_id, parent_window, title, options)
            .await
        {
            Ok(Some(results)) => Ok((XDG_DESKTOP_PORTAL_RESPONSE_SUCCESS, results)),
            Ok(None) => Ok((XDG_DESKTOP_PORTAL_RESPONSE_CANCELLED, BTreeMap::new())),
            Err(e) => {
                msg(&e);
                Ok((XDG_DESKTOP_PORTAL_RESPONSE_OTHER, BTreeMap::new()))
            }
        }
    }

    async fn save_file(
        &self,
        handle: ObjectPath<'_>,
        app_id: &str,
        parent_window: &str,
        title: &str,
        options: BTreeMap<&str, Value<'_>>,
    ) -> zbus::fdo::Result<(u32, BTreeMap<String, OwnedValue>)> {
        match self
            .save_file_impl(handle, app_id, parent_window, title, options)
            .await
        {
            Ok(Some(results)) => Ok((XDG_DESKTOP_PORTAL_RESPONSE_SUCCESS, results)),
            Ok(None) => Ok((XDG_DESKTOP_PORTAL_RESPONSE_CANCELLED, BTreeMap::new())),
            Err(e) => {
                msg(&e);
                Ok((XDG_DESKTOP_PORTAL_RESPONSE_OTHER, BTreeMap::new()))
            }
        }
    }

    // TODO: implement save_files
}

impl FileChooser {
    /// D-Bus requests will panic if `guest_share_root` is not absolute.
    pub fn new(guest_share_root: PathBuf) -> Self {
        FileChooser { guest_share_root }
    }

    /// Take a list of host URIs, share them with the guest using the
    /// document portal, then transform them into guest URIs.
    async fn transform_uris(
        &self,
        uris: &OwnedValue,
        writable: bool,
    ) -> Result<OwnedValue, String> {
        let uris = uris
            .downcast_ref::<Array>()
            .map_err(|e| format!("uris: {e}"))?;
        let mut uris: Vec<String> = uris
            .try_into()
            .map_err(|e| format!("members of uris: {e}"))?;

        for uri in uris.iter_mut() {
            let path = uri
                .strip_prefix("file://")
                .ok_or_else(|| format!("member of uris is not a file:// URL: {:?}", uri))?;
            let path = percent_decode(path.as_bytes());
            let path = PathBuf::from(OsString::from_vec(path.collect()));

            let path = share_file(path.clone(), writable)
                .await
                .map_err(|e| format!("adding {:?} to document portal: {e}", path))?;

            let guest_path = self.guest_share_root.join(path);
            // Potential panic is documented in FileChooser::new.
            *uri = Url::from_file_path(guest_path).unwrap().to_string();
        }

        let uris: Array = uris.into();
        // unwrap can only fail if dup fails, and we know uris doesn't
        // contain any file descriptors.
        Ok(OwnedValue::try_from(uris).unwrap())
    }

    async fn open_file_impl(
        &self,
        handle: ObjectPath<'_>,
        app_id: &str,
        parent_window: &str,
        title: &str,
        options: BTreeMap<&str, Value<'_>>,
    ) -> Result<Option<BTreeMap<String, OwnedValue>>, String> {
        let (response, mut results) = PROXY
            .get()
            .unwrap()
            .open_file(handle, app_id, parent_window, title, options)
            .await
            .map_err(|e| format!("backend: {e}"))?;

        match response {
            XDG_DESKTOP_PORTAL_RESPONSE_SUCCESS => {
                let writable = results
                    .get("writable")
                    .unwrap_or(&OwnedValue::from(false))
                    .downcast_ref::<bool>()
                    .map_err(|e| format!("writable from backend: {e}"))?;

                if let Some(uris) = results.get("uris") {
                    let uris = self.transform_uris(uris, writable).await?;
                    results.insert("uris".to_string(), uris);
                }

                Ok(Some(results))
            }

            XDG_DESKTOP_PORTAL_RESPONSE_CANCELLED => Ok(None),

            _ => {
                let msg = format!("Interaction ended with response {response}: {:?}", results);
                Err(msg)
            }
        }
    }

    async fn save_file_impl(
        &self,
        handle: ObjectPath<'_>,
        app_id: &str,
        parent_window: &str,
        title: &str,
        options: BTreeMap<&str, Value<'_>>,
    ) -> Result<Option<BTreeMap<String, OwnedValue>>, String> {
        let (response, mut results) = PROXY
            .get()
            .unwrap()
            .save_file(handle, app_id, parent_window, title, options)
            .await
            .map_err(|e| format!("backend: {e}"))?;

        match response {
            XDG_DESKTOP_PORTAL_RESPONSE_SUCCESS => {
                if let Some(uris) = results.get("uris") {
                    let uris = self.transform_uris(uris, true).await?;
                    results.insert("uris".to_string(), uris);
                }

                Ok(Some(results))
            }

            XDG_DESKTOP_PORTAL_RESPONSE_CANCELLED => Ok(None),

            _ => {
                let msg = format!("Interaction ended with response {response}: {:?}", results);
                Err(msg)
            }
        }
    }
}

pub async fn init(conn: &Connection) {
    PROXY
        .set(FileChooserProxy::new(conn).await.unwrap())
        .unwrap();
}
