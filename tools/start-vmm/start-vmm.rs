// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022-2024 Alyssa Ross <hi@alyssa.is>

use std::env::args_os;
use std::fs::File;
use std::os::unix::prelude::*;
use std::path::Path;
use std::process::exit;

use start_vmm::{create_api_socket, create_vm, prog_name, vm_command};

fn ex_usage() -> ! {
    eprintln!("Usage: start-vmm vm");
    exit(1);
}

/// # Safety
///
/// Takes ownership of the file descriptor used for readiness notification, so can
/// only be called once.
unsafe fn run() -> String {
    let mut args = args_os().skip(1);
    let Some(vm_name) = args.next() else {
        ex_usage();
    };
    if args.next().is_some() {
        ex_usage();
    }

    let vm_dir = Path::new("/run/vm/by-id").join(vm_name);

    let api_socket = match create_api_socket(&vm_dir) {
        Ok(api_socket) => api_socket,
        Err(e) => return e,
    };

    let ready_fd = File::from_raw_fd(3);

    if let Err(e) = create_vm(&vm_dir, ready_fd) {
        return e;
    }

    match vm_command(api_socket.into_raw_fd()) {
        Ok(mut command) => format!("failed to exec: {}", command.exec()),
        Err(e) => e,
    }
}

fn main() {
    eprintln!("{}: {}", prog_name(), unsafe { run() });
    exit(1);
}
