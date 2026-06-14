// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2026 Demi Marie Obenour <demiobenour@gmail.com>

use std::{
    ffi::{OsStr, OsString},
    os::unix::prelude::*,
    path::{Path, PathBuf},
};

use crate::cgroup::Cgroup;

mod cgroup;

fn check_path(path: &OsStr) -> Result<(), String> {
    if path.is_empty() {
        return Ok(());
    }

    for component in path.as_bytes().split(|&b| b == b'/') {
        match component {
            b"" | b"." | b".." => {
                return Err(format!("Path {path:?} has empty, ., or .. component"));
            }
            // Cannot happen: command line arguments have no NUL byte,
            // and /proc/self/cgroup having a NUL byte is a kernel bug.
            _ if component.contains(&b'\0') => panic!("Path {path:?} has NUL byte"),
            _ if component.len() > 255 => {
                return Err(format!(
                    "Path {path:?} has component {:?} that is longer than 255 bytes",
                    OsStr::from_bytes(component)
                ));
            }
            _ => {}
        }
    }

    Ok(())
}

/// Get the path of the cgroup for the provided command-line argument.
/// Returns an empty path if the path is "/", or if it is "." and the
/// current cgroup is "/".
///
/// # Errors
///
/// Fails if the provided path is invalid or empty, or if it is relative
/// and the local cgroup cannot be determined.
fn get_cgroup(cgroup_path: OsString) -> Result<PathBuf, String> {
    if cgroup_path.as_bytes().starts_with(b"/") {
        let mut cgroup_path = cgroup_path.into_vec();
        cgroup_path.remove(0);
        if cgroup_path.is_empty() {
            return Err("cgroup path cannot be /".to_owned());
        }
        let cgroup_path = OsString::from_vec(cgroup_path);
        check_path(&cgroup_path)?;
        Ok(cgroup_path.into())
    } else if cgroup_path.is_empty() {
        Err("cgroup path cannot be empty".to_owned())
    } else {
        check_path(&cgroup_path)?;
        let mut local_cgroup = local_cgroup()?;
        local_cgroup.push(cgroup_path);
        Ok(local_cgroup)
    }
}

/// Open the cgroup corresponding to the provided path.
/// It must have already been made relative to `/sys/fs/cgroup`.
///
/// # Errors
///
/// Fails if the cgroup operation fails.
fn open_cgroup(path: &Path, exclusive: bool) -> Result<Cgroup, String> {
    if path.as_os_str().is_empty() {
        Cgroup::new(exclusive)
    } else {
        let mut cgroup = Cgroup::new(false)?;
        cgroup.open_sub_cgroup(path, exclusive, false)?;
        Ok(cgroup)
    }
}

/// Open the cgroup corresponding to the provided path's parent.
/// It is made relative to the process's own cgroup if needed.
///
/// # Errors
///
/// Fails if the cgroup operation fails.
fn open_relative_cgroup(arg: OsString) -> Result<(PathBuf, Cgroup), String> {
    let path = get_cgroup(arg)?;
    let cgroup = open_cgroup(path.parent().expect("always has a parent"), true)?;
    Ok((path, cgroup))
}

fn main() {
    let mut args = std::env::args_os();
    let Some(prog_name) = args.next() else {
        eprintln!("No command line arguments (argv[0] is NULL)");
        std::process::exit(1);
    };
    match main_(&prog_name, args) {
        Ok(()) => {}
        Err(e) => {
            eprintln!("{prog_name:?}: {}", e);
            std::process::exit(1);
        }
    }
}

fn main_(prog_name: &OsStr, mut args: std::env::ArgsOs) -> Result<(), String> {
    match prog_name
        .as_bytes()
        .split(|&b| b == b'/')
        .next_back()
        .unwrap()
    {
        b"cgroup-s6-finish" => {
            return s6_finish(&mut args);
        }
        b"cgroup-setup" => {}
        b"cgroup-purge" => {
            if args.len() != 1 {
                return Err(format!(
                    "cgroup-purge takes one argument, got {}",
                    args.len()
                ));
            }
            let cgroup_path = args.next().unwrap();
            let (path, mut cgroup) = open_relative_cgroup(cgroup_path)?;
            let cgroup_target = Path::new(path.file_name().unwrap());
            return cgroup.purge(cgroup_target);
        }
        _ => {
            return Err(format!(
                "must be invoked as \"cgroup-setup\" \
                 \"cgroup-purge\", or \"cgroup-s6-finish\", \
                 got {prog_name:?}",
            ));
        }
    };
    let mut leaf = false;
    let mut cgroup_path;
    let mut delegate = false;
    let mut init_subtree = false;
    let mut child_name: Option<&'static OsStr> = None;
    let mut wait = true;
    loop {
        cgroup_path = args.next();
        let Some(ref arg_) = cgroup_path else {
            break;
        };
        let arg_ = arg_.as_bytes();
        if arg_ == b"--" {
            cgroup_path = args.next();
            break;
        }
        if !arg_.starts_with(b"-") {
            break;
        }

        if !arg_.starts_with(b"--") {
            return Err("takes no short options".to_owned());
        }

        match &arg_[2..] {
            b"leaf" => leaf = true,
            b"delegate" => delegate = true,
            b"init-subtree" => init_subtree = true,
            b"wait" => wait = true,
            b"no-wait" => wait = false,
            b"child-name" if child_name.is_none() => match args.next() {
                Some(arg) => child_name = Some(arg.leak()),
                None => return Err("--child-name: missing argument".to_owned()),
            },
            b"child-name" => return Err("--child-name: cannot be used twice".to_owned()),
            arg => match str::from_utf8(arg) {
                Ok(e) => return Err(format!("unknown long option {e:?}")),
                Err(_) => return Err("long option isn't UTF-8".to_owned()),
            },
        }
    }

    let default_child_name = OsStr::from_bytes(b"$inner.service");

    let child_name = Path::new(child_name.unwrap_or(default_child_name));

    let Some(mut cgroup_path) = cgroup_path else {
        return Err("have no positional arguments, expected at least 1".to_owned());
    };

    // Allow --init-subtree .
    if cgroup_path.as_bytes() == b"." && init_subtree && !leaf {
        cgroup_path = child_name.to_owned().into();
        leaf = true;
    }

    let (path, mut cgroup) = open_relative_cgroup(cgroup_path)?;
    let cgroup_target = Path::new(path.file_name().unwrap());
    cgroup
        .make_child(cgroup_target)
        .map_err(|e| format!("Cannot make child cgroup: {e}"))?;
    if wait {
        cgroup
            .wait_for_empty()
            .map_err(|e| format!("Cannot wait for {path:?} to be empty: {e}"))?;
    }
    let pid = std::process::id().to_string();
    if leaf {
        if args.len() != 0 {
            // If we aren't delegating any cgroups, don't create a sub-cgroup.
            cgroup
                .write_cgroup_value("cgroup.procs", &pid)
                .map_err(|e| format!("Cannot write to {path:?}/cgroup.procs: {e}"))?;
        }
    } else {
        // If the child process will need to manage cgroups itself, it will need
        // to set up a sub-cgroup due to the "no internal processes" rule.  It's
        // simplest to just do it automatically.
        cgroup.make_child(Path::new(child_name)).map_err(|e| {
            format!(
                "Cannot create child cgroup {}/{}: {e}",
                path.display(),
                child_name.display()
            )
        })?;
        if args.len() != 0 {
            cgroup
                .write_cgroup_value("cgroup.procs", &pid)
                .map_err(|e| {
                    format!(
                        "Cannot write to {}/{}/cgroup.procs: {e}",
                        path.display(),
                        child_name.display()
                    )
                })?;
        }
    }
    if !leaf {
        cgroup.enable_subtree_control(2)?;
    }
    if init_subtree {
        cgroup.enable_subtree_control(1)?;
    }
    if delegate {
        cgroup
            .enable_delegation(1)
            .map_err(|e| format!("Cannot enable cgroup delegation in {path:?}: {e}"))?;
    }
    let Some(program_name) = args.next() else {
        return Ok(());
    };
    let e = std::process::Command::new(&program_name).args(args).exec();
    Err(format!("Cannot spawn child {:?}: {}", program_name, e))
}

fn s6_finish(args: &mut std::env::ArgsOs) -> Result<(), String> {
    if args.len() < 3 {
        return Err(format!(
            "s6 finish scripts take at least 3 arguments, got {}",
            args.len()
        ));
    }
    let status = parse_digit_string(&args.next().unwrap(), "exit status")?;
    let signal = args.next().unwrap();
    let signal = if status == 256 {
        Some(parse_digit_string(&signal, "signal number")?)
    } else {
        None
    };
    let service = args.next().unwrap();

    let (path, mut cgroup) = open_relative_cgroup(service)?;
    let cgroup_target = Path::new(path.file_name().unwrap());
    let exit_125 = if let Some(signal) = signal {
        match signal as libc::c_int {
            libc::SIGBUS
            | libc::SIGFPE
            | libc::SIGABRT
            | libc::SIGTRAP
            | libc::SIGSEGV
            | libc::SIGILL => {
                // Process *crashed*, indicating a *possible exploit attempt*.
                // s6 should *not* restart it.  This is distinct from a Rust panic,
                // which is much less likely to indicate memory corruption.
                true
            }
            _ => false,
        }
    } else {
        false
    };
    if exit_125 {
        // Ignore panics.  Exit status is more important.
        // We already had a core dump.
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            match cgroup.purge(cgroup_target) {
                Ok(()) => {}
                Err(e) => {
                    eprintln!("cgroup-s6-finish: Failed to purge cgroup: {e}")
                }
            };
        }));
        std::process::exit(125)
    } else {
        cgroup.purge(cgroup_target)
    }
}

fn parse_digit_string(digits: &OsStr, msg: &str) -> Result<u16, String> {
    let checked = match str::from_utf8(digits.as_bytes()) {
        Ok(s) => s,
        Err(e) => return Err(format!("{msg} is not UTF-8: {e}")),
    };
    let r = checked
        .parse::<u16>()
        .map_err(|e| format!("{msg} {digits:?} is a bad 16-bit number: {e}"))?;
    match checked.as_bytes() {
        b"0" | [b'1'..=b'9', ..] => Ok(r),
        [b'0', ..] => Err(format!("{msg} {} has a leading 0", digits.display())),
        _ => Err(format!("{msg} {} starts with +", digits.display())),
    }
}

fn local_cgroup() -> Result<PathBuf, String> {
    let mut local_cgroup: Vec<u8> = std::fs::read("/proc/thread-self/cgroup")
        .map_err(|e| format!("cannot read /proc/thread-self/cgroup: {e}"))?;
    let local_cgroup_len = local_cgroup.len();
    if local_cgroup_len < 5
        || local_cgroup[..4] != *b"0::/"
        || local_cgroup[local_cgroup_len - 1] != b'\n'
        || local_cgroup[4..local_cgroup_len - 1].contains(&b'\n')
    {
        // It's possible to get here if the cgroup path contains a newline,
        // but that never happens in Spectrum.
        return Err(format!(
            "Invalid contents {local_cgroup:?} of /proc/thread-self/cgroup - \
             do you have cgroups v1 mounted instead of cgroups v2?"
        ));
    }

    local_cgroup.copy_within(4..local_cgroup_len - 1, 0);
    local_cgroup.truncate(local_cgroup_len - 5);
    let local_cgroup = OsString::from_vec(local_cgroup);
    check_path(&local_cgroup).unwrap();
    Ok(PathBuf::from(local_cgroup))
}
