// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022-2024 Alyssa Ross <hi@alyssa.is>

mod ch;
mod fork;
mod net;
mod s6;
mod unix;

use std::borrow::Cow;
use std::convert::TryInto;
use std::env::args_os;
use std::ffi::OsStr;
use std::fs::{remove_file, File};
use std::io::{self, ErrorKind};
use std::os::unix::net::UnixListener;
use std::os::unix::prelude::*;
use std::os::unix::process::parent_id;
use std::path::Path;
use std::process::{exit, Command};

use ch::{
    ConsoleConfig, DiskConfig, FsConfig, GpuConfig, MemoryConfig, PayloadConfig, VmConfig,
    VsockConfig,
};
use fork::double_fork;
use net::net_setup;
use s6::notify_readiness;
use unix::AsFdExt;

const SIGTERM: i32 = 15;

extern "C" {
    fn kill(pid: i32, sig: i32) -> i32;
}

pub fn prog_name() -> String {
    args_os()
        .next()
        .as_ref()
        .map(Path::new)
        .and_then(Path::file_name)
        .map(OsStr::to_string_lossy)
        .unwrap_or(Cow::Borrowed("start-vmm"))
        .into_owned()
}

pub fn create_api_socket(vm_dir: &Path) -> Result<UnixListener, String> {
    let path = vm_dir.join("vmm");

    let _ = remove_file(&path);
    let api_socket = UnixListener::bind(&path).map_err(|e| format!("creating API socket: {e}"))?;

    if let Err(e) = api_socket.clear_cloexec() {
        return Err(format!("clearing CLOEXEC on API socket fd: {}", e));
    }

    Ok(api_socket)
}

pub fn vm_config(vm_dir: &Path) -> Result<VmConfig, String> {
    let Some(vm_name) = vm_dir.file_name().unwrap().to_str() else {
        return Err(format!("VM dir {:?} is not valid UTF-8", vm_dir));
    };

    // A colon is used for namespacing vhost-user backends, so while
    // we have the VM name we enforce that it doesn't contain one.
    if vm_name.contains(':') {
        return Err(format!("VM name may not contain a colon: {:?}", vm_name));
    }

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
                        return Err(format!("illegal ',' character in path {:?}", entry));
                    }

                    Ok(DiskConfig {
                        path: entry,
                        readonly: true,
                    })
                })
                .collect::<Result<_, _>>()?,
            Err(e) => return Err(format!("reading directory {:?}: {}", blk_dir, e)),
        },
        fs: [FsConfig {
            tag: "virtiofs0",
            socket: format!("/run/service/vhost-user-fs/instance/{vm_name}/env/virtiofsd.sock"),
        }],
        gpu: vec![GpuConfig {
            socket: format!("/run/service/vhost-user-gpu/instance/{vm_name}/env/crosvm.sock"),
        }],
        memory: MemoryConfig {
            size: 1 << 30,
            shared: true,
        },
        net: match net_providers_dir.read_dir() {
            Ok(entries) => entries
                .into_iter()
                .map(|result| {
                    let provider_name = result
                        .map_err(|e| format!("examining directory entry: {}", e))?
                        .file_name()
                        .into_string()
                        .map_err(|name| format!("provider name {:?} is not UTF-8", name))?;

                    let provider_dir = vm_dir
                        .parent()
                        .unwrap()
                        .parent()
                        .unwrap()
                        .join("by-name")
                        .join(provider_name);

                    // SAFETY: we check the result.
                    let net = unsafe { net_setup(&provider_dir.as_path()) };
                    if net.fd == -1 {
                        let e = io::Error::last_os_error();
                        return Err(format!("setting up networking failed: {e}"));
                    }

                    Ok(net.try_into().unwrap())
                })
                // TODO: to support multiple net providers, we'll need
                // a better naming scheme for tap and bridge devices.
                .take(1)
                .collect::<Result<_, _>>()?,
            Err(e) if e.kind() == ErrorKind::NotFound => Default::default(),
            Err(e) => return Err(format!("reading directory {:?}: {e}", net_providers_dir)),
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
    })
}

fn create_vm_child_main(vm_dir: &Path, ready_fd: File, config: VmConfig) -> ! {
    if let Err(e) = ch::create_vm(vm_dir, config) {
        eprintln!("{}: creating VM: {e}", prog_name());
        // SAFETY: trivially safe.
        if unsafe { kill(parent_id() as _, SIGTERM) } == -1 {
            let e = io::Error::last_os_error();
            eprintln!("{}: killing cloud-hypervisor: {e}", prog_name());
        };
        exit(1);
    }

    if let Err(e) = notify_readiness(ready_fd) {
        eprintln!("{}: failed to notify readiness: {e}", prog_name());
        exit(1);
    }

    exit(0)
}

pub fn create_vm(vm_dir: &Path, ready_fd: File) -> Result<(), String> {
    let config = vm_config(vm_dir)?;

    // SAFETY: safe because we ensure we don't violate any invariants
    // concerning OS resources shared between processes, by only
    // passing data structs to the child main function.
    match unsafe { double_fork() } {
        e if e < 0 => Err(format!("double fork: {}", io::Error::from_raw_os_error(-e))),
        // SAFETY: create_vm_child_main can only be called once per process,
        // but this is a new process, so we know it hasn't been called before.
        0 => create_vm_child_main(vm_dir, ready_fd, config),
        _ => Ok(()),
    }
}

pub fn vm_command(api_socket_fd: RawFd) -> Result<Command, String> {
    let mut command = Command::new("cloud-hypervisor");
    command.args(["--api-socket", &format!("fd={api_socket_fd}")]);

    Ok(command)
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
