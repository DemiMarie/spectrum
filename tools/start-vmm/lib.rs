// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022-2024 Alyssa Ross <hi@alyssa.is>

mod ch;
mod net;
mod s6;

use std::borrow::Cow;
use std::convert::TryInto;
use std::env::args_os;
use std::ffi::OsStr;
use std::fs::File;
use std::io::{self, ErrorKind};
use std::path::Path;

use ch::{
    ConsoleConfig, DiskConfig, FsConfig, GpuConfig, LandlockConfig, MemoryConfig, PayloadConfig,
    VmConfig, VsockConfig,
};
use net::net_setup;

pub fn prog_name() -> String {
    args_os()
        .next()
        .as_ref()
        .map(Path::new)
        .and_then(Path::file_name)
        .map_or(Cow::Borrowed("start-vmm"), OsStr::to_string_lossy)
        .into_owned()
}

pub fn vm_config(vm_dir: &Path) -> Result<VmConfig, String> {
    let Some(vm_name) = vm_dir.file_name().unwrap().to_str() else {
        return Err(format!("VM dir {vm_dir:?} is not valid UTF-8"));
    };

    // A colon is used for namespacing vhost-user backends, so while
    // we have the VM name we enforce that it doesn't contain one.
    if vm_name.contains(':') {
        return Err(format!("VM name may not contain a colon: {vm_name:?}"));
    }

    let name_bytes = vm_name.as_bytes();

    let config_dir = vm_dir.join("config");
    let blk_dir = config_dir.join("blk");
    let kernel_path = config_dir.join("vmlinux");
    let net_providers_dir = config_dir.join("providers/net");

    Ok(VmConfig {
        console: ConsoleConfig {
            mode: "Pty",
            file: None,
        },
        disks: match blk_dir.read_dir() {
            Ok(entries) => entries
                .into_iter()
                .map(|result| {
                    Ok(result
                        .map_err(|e| format!("examining directory entry: {e}"))?
                        .path())
                })
                .filter(|result| {
                    result
                        .as_ref()
                        .map(|entry| entry.extension() == Some(OsStr::new("img")))
                        .unwrap_or(true)
                })
                .map(|result: Result<_, String>| {
                    let entry = result?.to_str().unwrap().to_string();

                    if entry.contains(',') {
                        return Err(format!("illegal ',' character in path {entry:?}"));
                    }

                    Ok(DiskConfig {
                        path: entry,
                        readonly: true,
                    })
                })
                .collect::<Result<_, _>>()?,
            Err(e) => return Err(format!("reading directory {blk_dir:?}: {e}")),
        },
        fs: [FsConfig {
            tag: "virtiofs0",
            socket: format!(
                "/run/service/vm-services/instance/{vm_name}/data/service/vhost-user-fs/env/virtiofsd.sock"
            ),
        }],
        gpu: vec![GpuConfig {
            socket: format!(
                "/run/service/vm-services/instance/{vm_name}/data/service/vhost-user-gpu/env/crosvm.sock"
            ),
        }],
        memory: MemoryConfig {
            size: 1 << 30,
            shared: true,
        },
        net: match net_providers_dir.read_dir() {
            Ok(_) => {
                // SAFETY: we check the result.
                let net = unsafe {
                    net_setup(
                        name_bytes.as_ptr().cast(),
                        name_bytes
                            .len()
                            .try_into()
                            .map_err(|e| format!("VM name too long: {e}"))?,
                    )
                };
                if net.fd == -1 {
                    let e = io::Error::last_os_error();
                    return Err(format!("setting up networking failed: {e}"));
                }

                vec![net.try_into().unwrap()]
            }
            Err(e) if e.kind() == ErrorKind::NotFound => Default::default(),
            Err(e) => return Err(format!("reading directory {net_providers_dir:?}: {e}")),
        },
        payload: PayloadConfig {
            kernel: kernel_path.to_str().unwrap().to_string(),
            #[cfg(target_arch = "x86_64")]
            cmdline: "console=ttyS0 root=PARTLABEL=root",
            #[cfg(not(target_arch = "x86_64"))]
            cmdline: "root=PARTLABEL=root",
        },
        serial: ConsoleConfig {
            mode: "File",
            file: Some(format!("/run/{vm_name}.log")),
        },
        vsock: VsockConfig {
            cid: 3,
            socket: vm_dir.join("vsock").into_os_string().into_string().unwrap(),
        },
        landlock_enable: true,
        landlock_rules: vec![
            LandlockConfig {
                path: "/sys/devices",
                access: "rw",
            },
            LandlockConfig {
                path: "/dev/vfio",
                access: "rw",
            },
        ],
    })
}

pub fn create_vm(vm_dir: &Path, ready_fd: File) -> Result<(), String> {
    let config = vm_config(vm_dir)?;

    ch::create_vm(vm_dir, ready_fd, config).map_err(|e| format!("creating VM: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    use std::fs::OpenOptions;

    #[test]
    fn test_vm_name_colon() {
        let ready_fd = OpenOptions::new().write(true).open("/dev/null").unwrap();
        let e = create_vm(Path::new("/:vm"), ready_fd).unwrap_err();
        assert!(e.contains("colon"), "unexpected error: {:?}", e);
    }
}
