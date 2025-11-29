// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022-2024 Alyssa Ross <hi@alyssa.is>
// SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>

use std::ffi::OsStr;
use std::fs::File;
use std::io::Write;
use std::os::unix::prelude::*;
use std::path::Path;
use std::process::{Command, Stdio};

use miniserde::{Serialize, json};

use crate::net::MacAddress;
use crate::s6::notify_readiness;

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
    pub vhost_user: bool,
    pub vhost_socket: String,
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
pub struct LandlockConfig {
    pub path: &'static str,
    pub access: &'static str,
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
    pub landlock_enable: bool,
    pub landlock_rules: Vec<LandlockConfig>,
}

fn command(vm_dir: &Path, s: impl AsRef<OsStr>) -> Command {
    let mut command = Command::new("ch-remote");
    command.stdin(Stdio::null());
    command.arg("--api-socket");
    command.arg(vm_dir.join("vmm"));
    command.arg(s);
    command
}

pub fn create_vm(vm_dir: &Path, ready_fd: File, config: VmConfig) -> Result<(), String> {
    let mut ch_remote = command(vm_dir, "create")
        .args(["--", "-"])
        .stdin(Stdio::piped())
        .spawn()
        .map_err(|e| format!("failed to start ch-remote: {e}"))?;

    let json = json::to_string(&config);
    write!(ch_remote.stdin.as_ref().unwrap(), "{json}")
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

    notify_readiness(ready_fd)?;

    Ok(())
}
