// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022-2024 Alyssa Ross <hi@alyssa.is>

use std::env::args_os;
use std::fs::File;
use std::os::unix::prelude::*;
use std::path::Path;
use std::process::exit;

use start_vmm::{create_vm, prog_name};

fn ex_usage() -> ! {
    eprintln!("Usage: start-vmm vm");
    exit(1);
}

/// # Safety
///
/// Takes ownership of the file descriptor used for readiness notification, so can
/// only be called once.
unsafe fn run() -> Result<(), String> {
    let mut args = args_os().skip(1);
    let Some(vm_name) = args.next() else {
        ex_usage();
    };
    if args.next().is_some() {
        ex_usage();
    }

    let vm_dir = Path::new("/run/vm/by-id").join(vm_name);
    let ready_fd = File::from_raw_fd(3);

    create_vm(&vm_dir, ready_fd)
}

fn main() {
    if let Err(e) = unsafe { run() } {
        eprintln!("{}: {e}", prog_name());
        exit(1);
    }
}
