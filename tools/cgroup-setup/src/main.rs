// SPDX-FileCopyrightText: 2026 Demi Marie Obenour <demiobenour@gmail.com>
// SPDX-License-Identifier: EUPL-1.2+

mod cgroup;

use cgroup::{Cgroup, OpenFlags, openat2_simple, write_value};
use rustix::{
    fs::{FlockOperation, Mode, XattrFlags},
    io::Errno,
};
use std::{
    env::ArgsOs,
    os::unix::prelude::*,
    path::{Path, PathBuf},
};

fn exec_in_cgroup(
    mut args: std::iter::Peekable<ArgsOs>,
    cgroup: Option<&dyn AsFd>,
) -> Result<(), String> {
    let Some(program_name) = args.next() else {
        return Ok(());
    };
    if let Some(cgroup) = cgroup {
        let pid = std::process::id().to_string();
        write_value(
            cgroup,
            Path::new("$inner.service/cgroup.procs"),
            pid.as_bytes(),
        )
        .map_err(|e| format!("Cannot move process to child cgroup: {e}"))?;
    }
    let e = std::process::Command::new(&program_name).args(args).exec();
    Err(format!("Cannot exec child {program_name:?}: {e}"))
}

// Check that the path is canonical,
// then split it into basename and filename.
fn split_canonical_path(path: &Path) -> Result<(&Path, &Path), String> {
    let bytes = path.as_os_str().as_bytes();
    // Path::components() skips ., so use string manipulation instead.
    for component in bytes[path.is_absolute() as usize..].split(|&b| b == b'/') {
        if matches!(component, b"" | b"." | b"..") {
            return Err(format!("cgroup path {path:?} isn't canonical"));
        }
    }
    Ok((path.parent().unwrap(), Path::new(path.file_name().unwrap())))
}

fn cgroup_setup(args: ArgsOs) -> Result<(), String> {
    let mut wait = true;
    let mut args = args.peekable();
    while let Some(arg) = args.peek() {
        if !arg.as_bytes().starts_with(b"-") {
            break;
        }
        let arg = args.next().unwrap();
        let Some(option) = arg.as_bytes().strip_prefix(b"--") else {
            return Err("takes no short options".to_owned());
        };
        match option {
            b"" => break,
            b"no-wait" => wait = false,
            _ => return Err(format!("unknown long option {arg:?}")),
        }
    }
    let Some(cgroup_path) = args.next().map(PathBuf::from) else {
        return Err("have no positional arguments, expected at least 1".to_owned());
    };

    let (parent_cgroup_path, child_cgroup_path) = split_canonical_path(&cgroup_path)?;
    let cgroup = Cgroup::new(parent_cgroup_path)?;
    match rustix::fs::mkdirat(&cgroup, child_cgroup_path, Mode::from_raw_mode(0o755)) {
        Ok(()) | Err(Errno::EXIST) => {}
        Err(e) => {
            return Err(format!(
                "Cannot create child cgroup {child_cgroup_path:?}: {e}"
            ));
        }
    }

    let child = openat2_simple(&cgroup, child_cgroup_path, OpenFlags::Directory)
        .map_err(|e| format!("Cannot open child cgroup: {e}"))?;

    // While waiting, hold an exclusive lock on the child.
    // This avoids two processes both waiting for the same cgroup to become
    // empty, then execing processes in the same cgroup.
    rustix::fs::flock(&child, FlockOperation::LockExclusive)
        .map_err(|e| format!("Cannot take an exclusive lock on child cgroup: {e}"))?;
    if wait {
        Cgroup::wait_for_empty(&child)
            .map_err(|e| format!("Cannot wait for {parent_cgroup_path:?} to be empty: {e}"))?;
    }

    // systemd-aware programs expect to have user.delegate=1
    rustix::fs::fsetxattr(&child, c"user.delegate", b"1", XattrFlags::empty())
        .map_err(|e| format!("Cannot enable cgroup delegation: {e}"))?;

    // If the child process will need to manage cgroups itself, it will need
    // to set up a sub-cgroup due to the "no internal processes" rule.  It's
    // simplest to just do it automatically.  If the cgroup already exists,
    // that isn't an error.
    match rustix::fs::mkdirat(&child, cgroup::DEFAULT_LEAF, Mode::from_raw_mode(0o755)) {
        Ok(()) | Err(Errno::EXIST) => {}
        Err(e) => return Err(format!("Cannot create $inner.service cgroup: {e}")),
    }

    exec_in_cgroup(args, Some(&child))
}

fn cgroup_purge(mut args: ArgsOs) -> Result<(), String> {
    if args.len() != 1 {
        return Err("usage: cgroup-purge CGROUP_TO_PURGE".to_owned());
    }
    let arg = args.next().unwrap();
    let (parent, child) = split_canonical_path(Path::new(&arg))?;
    Cgroup::new(parent)?.purge_child(child)
}

fn run(prog_name: &Path, args: ArgsOs) -> Result<(), String> {
    match prog_name.file_name().map(|f| f.as_bytes()) {
        Some(b"cgroup-setup") => cgroup_setup(args),
        Some(b"cgroup-purge") => cgroup_purge(args),
        _ => Err(format!(
            "must be invoked as \"cgroup-setup\" or \
                 \"cgroup-purge\", got {prog_name:?}",
        )),
    }
}

fn main() {
    let mut args = std::env::args_os();
    let Some(prog_name) = args.next() else {
        eprintln!("No command line arguments (argv[0] is NULL)");
        std::process::exit(1);
    };
    match run(Path::new(&prog_name), args) {
        Ok(()) => {}
        Err(e) => {
            eprintln!("{prog_name:?}: {}", e);
            std::process::exit(1);
        }
    }
}
