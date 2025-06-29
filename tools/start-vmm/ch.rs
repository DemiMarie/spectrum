// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022-2024 Alyssa Ross <hi@alyssa.is>

use std::convert::{TryFrom, TryInto};
use std::ffi::{OsStr, OsString};
use std::io::Write;
use std::mem::take;
use std::num::NonZeroI32;
use std::os::raw::c_int;
use std::os::unix::prelude::*;
use std::path::Path;
use std::process::{Command, Stdio};
use std::string::FromUtf8Error;

use miniserde::{json, Serialize};

use crate::net::MacAddress;

// Trivially safe.
const EPERM: NonZeroI32 = NonZeroI32::new(1).unwrap();
const EPROTO: NonZeroI32 = NonZeroI32::new(71).unwrap();

#[derive(Serialize)]
pub struct ConsoleConfig {
    pub mode: &'static str,
    pub file: Option<String>,
}

#[derive(Serialize)]
pub struct DiskConfig {
    pub path: String,
    pub readonly: bool,
}

#[derive(Serialize)]
pub struct FsConfig {
    pub socket: String,
    pub tag: &'static str,
}

#[derive(Serialize)]
pub struct GpuConfig {
    pub socket: String,
}

#[derive(Serialize)]
pub struct NetConfig {
    pub fd: RawFd,
    pub id: String,
    pub mac: MacAddress,
}

#[derive(Serialize)]
pub struct MemoryConfig {
    pub size: i64,
    pub shared: bool,
}

#[derive(Serialize)]
pub struct PayloadConfig {
    pub kernel: String,
    pub cmdline: &'static str,
}

#[derive(Serialize)]
pub struct VsockConfig {
    pub cid: u32,
    pub socket: String,
}

#[derive(Serialize)]
pub struct VmConfig {
    pub console: ConsoleConfig,
    pub disks: Vec<DiskConfig>,
    pub fs: [FsConfig; 1],
    pub gpu: Vec<GpuConfig>,
    pub memory: MemoryConfig,
    pub net: Vec<NetConfig>,
    pub payload: PayloadConfig,
    pub serial: ConsoleConfig,
    pub vsock: VsockConfig,
}

fn command(vm_dir: &Path, s: impl AsRef<OsStr>) -> Command {
    let mut command = Command::new("ch-remote");
    command.stdin(Stdio::null());
    command.arg("--api-socket");
    command.arg(vm_dir.join("vmm"));
    command.arg(s);
    command
}

pub fn create_vm(vm_dir: &Path, mut config: VmConfig) -> Result<(), String> {
    // Net devices can't be created from file descriptors in vm.create.
    // https://github.com/cloud-hypervisor/cloud-hypervisor/issues/5523
    let nets = take(&mut config.net);

    let mut ch_remote = command(vm_dir, "create")
        .args(["--", "-"])
        .stdin(Stdio::piped())
        .spawn()
        .map_err(|e| format!("failed to start ch-remote: {e}"))?;

    let json = json::to_string(&config);
    write!(ch_remote.stdin.as_ref().unwrap(), "{}", json)
        .map_err(|e| format!("writing to ch-remote's stdin: {e}"))?;

    let status = ch_remote
        .wait()
        .map_err(|e| format!("waiting for ch-remote: {e}"))?;
    if !status.success() {
        if let Some(code) = status.code() {
            return Err(format!("ch-remote exited {code}"));
        } else {
            let signal = status.signal().unwrap();
            return Err(format!("ch-remote killed by signal {signal}"));
        }
    }

    for net in nets {
        add_net(vm_dir, &net).map_err(|e| format!("failed to add net: {e}"))?;
    }

    Ok(())
}

pub fn add_net(vm_dir: &Path, net: &NetConfig) -> Result<(), NonZeroI32> {
    let mut ch_remote = command(vm_dir, "add-net")
        .arg(format!("fd={},id={},mac={}", net.fd, net.id, net.mac))
        .stdout(Stdio::piped())
        .spawn()
        .or(Err(EPERM))?;

    if let Ok(ch_remote_status) = ch_remote.wait() {
        if ch_remote_status.success() {
            return Ok(());
        }
    }

    Err(EPROTO)
}

#[repr(C)]
pub struct NetConfigC {
    pub fd: RawFd,
    pub id: [u8; 16],
    pub mac: MacAddress,
}

impl<'a> TryFrom<&'a NetConfigC> for NetConfig {
    type Error = FromUtf8Error;

    fn try_from(c: &'a NetConfigC) -> Result<NetConfig, Self::Error> {
        let nul_index = c.id.iter().position(|&c| c == 0).unwrap_or(c.id.len());
        Ok(NetConfig {
            fd: c.fd,
            id: String::from_utf8(c.id[..nul_index].to_vec())?,
            mac: c.mac,
        })
    }
}

impl TryFrom<NetConfigC> for NetConfig {
    type Error = FromUtf8Error;

    fn try_from(c: NetConfigC) -> Result<NetConfig, Self::Error> {
        Self::try_from(&c)
    }
}

/// # Safety
///
/// - `net.fd` must be a valid file descriptor.
/// - `net.id` must point to a valid C string.
#[export_name = "ch_add_net"]
unsafe extern "C" fn add_net_c(vm_dir: &&Path, net: &NetConfigC) -> c_int {
    if let Err(e) = add_net(vm_dir, &net.try_into().unwrap()) {
        e.get()
    } else {
        0
    }
}

/// # Safety
///
/// `id` must be a device ID obtained by calling `add_net_c`.  After
/// calling `device_free`, the pointer is no longer valid.
#[export_name = "ch_device_free"]
unsafe extern "C" fn device_free(id: Option<&mut OsString>) {
    if let Some(id) = id {
        drop(Box::from_raw(id))
    }
}
