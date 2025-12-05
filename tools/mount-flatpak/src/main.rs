// SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>
// SPDX-License-Identifier: EUPL-1.2+

//! Flatpak installations look like this:
//!
//! ```text
//! flatpak/
//! ├── app/
//! │   └── org.gnome.TextEditor/
//! │       ├── current -> x86_64/stable
//! │       └── x86_64/
//! │           └── stable/
//! │               ├── 0029140121b39f5b7cf4d44fd46b0708eee67f395b5e1291628612a0358fb909/
//! │               │   └── …
//! │               └── active -> 0029140121b39f5b7cf4d44fd46b0708eee67f395b5e1291628612a0358fb909
//! ├── db/
//! ├── exports/
//! │   └── …
//! ├── repo
//! │   ├── config
//! │   ├── objects
//! │   ├── tmp
//! │   │   └── cache
//! │   │       └── …
//! │   └── …
//! └── runtime
//!     ├── org.gnome.Platform
//!     │   └── x86_64
//!     │       └── 49
//!     │           ├── active -> bf6aa432cb310726f4ac0ec08cc88558619e1d4bd4b964e27e95187ecaad5400
//!     │           └── bf6aa432cb310726f4ac0ec08cc88558619e1d4bd4b964e27e95187ecaad5400
//!     │               └── …
//!     └── …
//! ```
//!
//! The purpose of this program is to use bind mounts to construct a
//! Flatpak installation containing only a single application and
//! runtime, which can be passed through to a VM without exposing
//! other installed applications.

mod keyfile;
mod metadata;

use std::borrow::Cow;
use std::env::{ArgsOs, args_os};
use std::ffi::OsStr;
use std::io;
use std::os::unix::prelude::*;
use std::path::{Path, PathBuf};
use std::process::exit;

use pathrs::Root;
use pathrs::flags::{OpenFlags, ResolverFlags};
use rustix::fs::{CWD, FileType, fstat};
use rustix::mount::{MoveMountFlags, OpenTreeFlags, move_mount, open_tree};

use metadata::extract_runtime;

fn ex_usage() -> ! {
    eprintln!("Usage: mount-flatpak userdata installation app");
    exit(1);
}

fn mount_commit(
    source_commit: &dyn AsFd,
    target_installation: &Root,
    path: &Path,
) -> Result<(), String> {
    let source_commit_tree = open_tree(
        source_commit,
        "",
        OpenTreeFlags::AT_EMPTY_PATH
            | OpenTreeFlags::OPEN_TREE_CLONE
            | OpenTreeFlags::OPEN_TREE_CLOEXEC
            | OpenTreeFlags::AT_RECURSIVE,
    )
    .map_err(|e| format!("cloning source commit tree: {e}"))?;
    let target_commit_dir = target_installation
        .mkdir_all(path, &PermissionsExt::from_mode(0o700))
        .map_err(|e| format!("creating target commit directory: {e}"))?;
    move_mount(
        source_commit_tree,
        "",
        target_commit_dir,
        "",
        MoveMountFlags::MOVE_MOUNT_F_EMPTY_PATH | MoveMountFlags::MOVE_MOUNT_T_EMPTY_PATH,
    )
    .map_err(|e| format!("mounting commit: {e}"))
}

fn run(mut args: ArgsOs) -> Result<(), String> {
    let Some(user_data_path) = args.next().map(PathBuf::from) else {
        ex_usage();
    };
    let Some(installation_path) = args.next().map(PathBuf::from) else {
        ex_usage();
    };
    let Some(app) = args.next() else {
        ex_usage();
    };
    if args.next().is_some() {
        ex_usage();
    }

    let user_data = Root::open(&user_data_path)
        .map_err(|e| format!("opening user data partition: {e}"))?
        .with_resolver_flags(ResolverFlags::NO_SYMLINKS);

    let source_installation_dir = user_data
        .open_subpath(&installation_path, OpenFlags::O_PATH)
        .map(Root::from_fd)
        .map_err(|e| format!("opening source flatpak installation: {e}"))?
        .with_resolver_flags(ResolverFlags::NO_SYMLINKS);

    std::fs::create_dir("flatpak")
        .map_err(|e| format!("creating target flatpak installation: {e}"))?;

    let target_installation_dir = open_tree(
        CWD,
        "flatpak",
        OpenTreeFlags::OPEN_TREE_CLONE
            | OpenTreeFlags::OPEN_TREE_CLOEXEC
            | OpenTreeFlags::AT_RECURSIVE
            | OpenTreeFlags::AT_SYMLINK_NOFOLLOW,
    )
    .map_err(|e| format!("opening target flatpak installation: {e}"))?;
    let target_installation_dir =
        Root::from_fd(target_installation_dir).with_resolver_flags(ResolverFlags::NO_SYMLINKS);

    let mut full_app_path = PathBuf::from("app");
    full_app_path.push(&app);
    full_app_path.push("current");
    let arch_and_branch = source_installation_dir
        .readlink(&full_app_path)
        .map_err(|e| format!("reading current app arch and branch: {e}"))?;
    let mut components = arch_and_branch.components();
    let arch = components.next().unwrap().as_os_str();
    let branch = components.as_path().as_os_str();
    if branch.is_empty() {
        return Err("can't infer branch from \"current\" link".to_string());
    }

    full_app_path.pop();
    full_app_path.push(&arch_and_branch);
    full_app_path.push("active");
    let commit = source_installation_dir
        .readlink(&full_app_path)
        .map_err(|e| format!("reading active app commit: {e}"))?
        .into_os_string();

    full_app_path.pop();
    full_app_path.push(&commit);
    let source_app_dir = source_installation_dir
        .resolve(&full_app_path)
        .map_err(|e| format!("opening source app directory: {e}"))?;

    let metadata = source_installation_dir
        .resolve(full_app_path.join("metadata"))
        .map_err(|e| format!("resolving app metadata: {e}"))?;

    let metadata_stat =
        fstat(&metadata).map_err(|e| format!("checking app metadata is a regular file: {e}"))?;
    let metadata_type = FileType::from_raw_mode(metadata_stat.st_mode);
    if !metadata_type.is_file() {
        let e = format!("type of app metadata is {metadata_type:?}, not RegularFile");
        return Err(e);
    }
    let metadata = metadata
        .reopen(OpenFlags::O_RDONLY)
        .map_err(|e| format!("opening app metadata: {e}"))?;

    let runtime =
        extract_runtime(metadata).map_err(|e| format!("reading runtime from metadata: {e}"))?;

    let mut full_runtime_path = PathBuf::from("runtime");
    full_runtime_path.push(runtime);
    full_runtime_path.push("active");
    let runtime_commit = source_installation_dir
        .readlink(&full_runtime_path)
        .map_err(|e| format!("reading active runtime commit: {e}"))?
        .into_os_string();

    full_runtime_path.pop();
    full_runtime_path.push(&runtime_commit);
    let source_runtime_dir = source_installation_dir
        .resolve(&full_runtime_path)
        .map_err(|e| format!("opening source runtime directory: {e}"))?;

    mount_commit(&source_app_dir, &target_installation_dir, &full_app_path)?;
    mount_commit(
        &source_runtime_dir,
        &target_installation_dir,
        &full_runtime_path,
    )?;

    target_installation_dir
        .mkdir_all("repo/objects", &PermissionsExt::from_mode(0o700))
        .map_err(|e| format!("creating repo/objects: {e}"))?;
    target_installation_dir
        .mkdir_all("repo/tmp/cache", &PermissionsExt::from_mode(0o700))
        .map_err(|e| format!("creating repo/tmp/cache: {e}"))?;
    let config_target = target_installation_dir
        .create_file(
            "repo/config",
            OpenFlags::O_WRONLY | OpenFlags::O_CLOEXEC,
            &PermissionsExt::from_mode(0o700),
        )
        .map_err(|e| format!("creating repo/config: {e}"))?;
    let config_source_path = env!("MOUNT_FLATPAK_CONFIG_PATH");
    let config_source = open_tree(
        CWD,
        config_source_path,
        OpenTreeFlags::OPEN_TREE_CLONE | OpenTreeFlags::OPEN_TREE_CLOEXEC,
    )
    .map_err(|e| format!("opening {config_source_path}: {e}"))?;
    move_mount(
        config_source,
        "",
        config_target,
        "",
        MoveMountFlags::MOVE_MOUNT_F_EMPTY_PATH | MoveMountFlags::MOVE_MOUNT_T_EMPTY_PATH,
    )
    .map_err(|e| format!("mounting config: {e}"))?;

    let mut attr = libc::mount_attr {
        attr_clr: libc::MOUNT_ATTR_NOSYMFOLLOW,
        attr_set: libc::MOUNT_ATTR_RDONLY | libc::MOUNT_ATTR_NODEV,
        propagation: libc::MS_SLAVE,
        userns_fd: 0,
    };
    let empty = b"\0";
    // SAFETY: we pass a valid FD, valid C string, and a valid mutable pointer with the
    // correct size.
    unsafe {
        let r = libc::syscall(
            libc::SYS_mount_setattr,
            target_installation_dir.as_fd().as_raw_fd() as libc::c_long,
            empty.as_ptr() as *const libc::c_char,
            (libc::AT_EMPTY_PATH | libc::AT_RECURSIVE) as libc::c_long,
            &mut attr as *mut libc::mount_attr,
            size_of::<libc::mount_attr>() as libc::c_long,
        );
        if r == -1 {
            return Err(format!(
                "setting target mount attributes: {}",
                io::Error::last_os_error()
            ));
        }
    }
    move_mount(
        target_installation_dir,
        "",
        CWD,
        "flatpak",
        MoveMountFlags::MOVE_MOUNT_F_EMPTY_PATH,
    )
    .map_err(|e| format!("mounting target installation dir: {e}"))?;

    std::fs::create_dir("params").map_err(|e| format!("creating params directory: {e}"))?;
    std::fs::write("params/id", app.as_bytes()).map_err(|e| format!("writing params/id: {e}"))?;
    std::fs::write("params/commit", commit.as_bytes())
        .map_err(|e| format!("writing params/commit: {e}"))?;
    std::fs::write("params/arch", arch.as_bytes())
        .map_err(|e| format!("writing params/arch: {e}"))?;
    std::fs::write("params/branch", branch.as_bytes())
        .map_err(|e| format!("writing params/branch: {e}"))?;
    std::fs::write("params/runtime-commit", runtime_commit.as_bytes())
        .map_err(|e| format!("writing params/runtime-commit: {e}"))?;

    Ok(())
}

fn main() {
    let mut args = args_os();

    let prog_name = args
        .next()
        .as_ref()
        .map(Path::new)
        .and_then(Path::file_name)
        .map_or(Cow::Borrowed("mount-flatpak"), OsStr::to_string_lossy)
        .into_owned();

    if let Err(e) = run(args) {
        eprintln!("{prog_name}: {e}");
        exit(1);
    }
}
