// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022-2024 Alyssa Ross <hi@alyssa.is>

use std::env::args_os;
use std::fs::File;
use std::os::fd::OwnedFd;
use std::path::Path;
use std::process::exit;

use start_vmm::{create_vm, prog_name, get_open_fd};

fn ex_usage() -> ! {
    eprintln!("Usage: start-vmm vm");
    exit(1);
}

fn run(f: OwnedFd) -> Result<(), String> {
    let mut args = args_os().skip(1);
    let Some(vm_name) = args.next() else {
        ex_usage();
    };
    if args.next().is_some() {
        ex_usage();
    }

    let vm_dir = Path::new("/run/vm/by-id").join(vm_name);
    let ready_fd = File::from(f);

    create_vm(&vm_dir, ready_fd)
}

fn main() {
    // SAFETY: this is the start of main().
    let f = unsafe { get_open_fd(3) };
    if let Err(e) = run(f.expect("caller bug: no readiness FD provided")) {
        eprintln!("{}: {e}", prog_name());
        exit(1);
    }
}
