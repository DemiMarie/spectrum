// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2026 Demi Marie Obenour <demiobenour@gmail.com>

use std::ffi::OsStr;
use std::fmt::Display;
use std::fs::File;
use std::io::{Read as _, Seek as _, Write as _};
use std::os::unix::prelude::*;

use std::path::{Component, Path, PathBuf};

use rustix::fs::{AtFlags, FlockOperation, XattrFlags};
use rustix::{
    fs::{Mode, OFlags, ResolveFlags},
    io::Errno,
};

#[derive(Debug)]
pub(crate) struct Cgroup {
    path: PathBuf,
    fd: Vec<(OwnedFd, bool)>,
}

impl AsFd for Cgroup {
    fn as_fd(&self) -> BorrowedFd<'_> {
        self.fd.last().unwrap().0.as_fd()
    }
}

fn assert_single_component(component: &[u8]) {
    match component {
        b"" | b"." | b".." => panic!("bad component"),
        _ if component.contains(&b'\0') => panic!("NUL in component"),
        _ if component.contains(&b'/') => panic!("/ in component"),
        _ => {}
    }
}

impl Cgroup {
    pub fn new(exclusive: bool) -> Result<Self, String> {
        let cgroup_root = rustix::fs::openat2(
            rustix::fs::CWD,
            Path::new("/sys/fs/cgroup"),
            OFlags::DIRECTORY | OFlags::RDONLY | OFlags::CLOEXEC | OFlags::NOFOLLOW,
            Mode::empty(),
            ResolveFlags::NO_MAGICLINKS | ResolveFlags::NO_SYMLINKS,
        )
        .map_err(|e| format!("Cannot open /sys/fs/cgroup: {e}"))?;

        let lock_operation = if exclusive {
            FlockOperation::LockExclusive
        } else {
            FlockOperation::LockShared
        };
        rustix::fs::flock(cgroup_root.as_fd(), lock_operation)
            .map_err(|e| format!("Cannot lock /sys/fs/cgroup: {e}"))?;
        Ok(Self {
            path: PathBuf::from("/sys/fs/cgroup"),
            fd: vec![(cgroup_root, exclusive)],
        })
    }

    pub fn enable_delegation(&self, depth: usize) -> Result<(), Errno> {
        let (fd, exclusive) = &self.fd[self.fd.len() - depth];
        assert!(exclusive);
        rustix::fs::fsetxattr(fd.as_fd(), c"user.delegate", b"1", XattrFlags::empty())
    }

    pub fn enable_subtree_control(&self, depth: usize) -> Result<(), String> {
        let (fd, exclusive) = &self.fd[self.fd.len() - depth];
        assert!(exclusive);
        let p = Path::new("cgroup.controllers");
        let mut buf = self.read_control_file(fd.as_fd(), p)?;
        let mut subtree = vec![];
        if buf.ends_with(b"\n") {
            buf.pop();
        }
        for controller in buf.split(|&b| b == b' ').filter(|e| !e.is_empty()) {
            for &c in controller {
                if c <= b' ' || c >= 0x7F {
                    return Err(format!("Bad byte {c} in cgroup.controllers"));
                }
            }
            if !subtree.is_empty() {
                subtree.push(b' ');
            }
            subtree.push(b'+');
            subtree.extend_from_slice(controller);
        }
        if !subtree.is_empty() {
            self.write_cgroup_value("cgroup.subtree_control", str::from_utf8(&subtree).unwrap())?;
        }
        Ok(())
    }

    pub fn read_control_file(&self, fd: BorrowedFd, p: &Path) -> Result<Vec<u8>, String> {
        let mut buf = Vec::new();
        let err = |e: &dyn Display, p: &Path, msg: &str| {
            let path = self.path.join(p);
            format!("Cannot {msg} {path:?}: {e}")
        };
        File::from(open_subtree_raw(Path::new(p), fd.as_fd()).map_err(|e| err(&e, p, "open"))?)
            .read_to_end(&mut buf)
            .map_err(|e| err(&e, p, "read"))?;
        Ok(buf)
    }

    /// Open a single component as a sub-cgroup
    fn open_sub_cgroup_raw(&self, access: OFlags, component: &[u8]) -> Result<OwnedFd, Errno> {
        assert_single_component(component);
        rustix::fs::openat2(
            self.as_fd(),
            Path::new(OsStr::from_bytes(component)),
            OFlags::CLOEXEC | OFlags::NOFOLLOW | access,
            Mode::empty(),
            ResolveFlags::NO_SYMLINKS
                | ResolveFlags::NO_MAGICLINKS
                | ResolveFlags::BENEATH
                | ResolveFlags::NO_XDEV,
        )
    }

    pub fn open_sub_cgroup(
        &mut self,
        path: &std::path::Path,
        exclusive: bool,
        allow_missing: bool,
    ) -> Result<bool, String> {
        let mut iter = path.components().peekable();
        while let Some(component) = iter.next() {
            let component = match component {
                Component::Normal(component) => component,
                _ => unreachable!(),
            };
            let sub_fd = match self
                .open_sub_cgroup_raw(OFlags::DIRECTORY | OFlags::RDONLY, component.as_bytes())
            {
                Ok(sub_fd) => {
                    self.path.push(component);
                    sub_fd
                }
                Err(Errno::NOENT) if allow_missing => return Ok(false),
                Err(e) => {
                    return Err(format!(
                        "Cannot open sub-cgroup {component:?} of {:?}: {e}",
                        self.path
                    ));
                }
            };
            let exclusive = exclusive && iter.peek().is_none();
            let lock_operation = if exclusive {
                FlockOperation::LockExclusive
            } else {
                FlockOperation::LockShared
            };
            rustix::fs::flock(sub_fd.as_fd(), lock_operation).map_err(|e| {
                let msg = format!("Cannot lock sub-cgroup {:?}: {e}", self.path);
                self.path.pop();
                msg
            })?;
            self.fd.push((sub_fd, exclusive));
        }
        Ok(true)
    }

    pub fn open_subtree(&self, path: &std::path::Path) -> Result<OwnedFd, Errno> {
        let dirfd = self.as_fd();
        open_subtree_raw(path, dirfd)
    }

    fn exclusive(&self) -> bool {
        self.fd.last().unwrap().1
    }

    pub fn joined_path(&self, p: &Path) -> PathBuf {
        let mut owned_p = self.path.clone();
        owned_p.push(p);
        owned_p
    }

    pub fn wait_for_empty(&self) -> std::io::Result<()> {
        assert!(self.exclusive());
        let wait_file = self.open_subtree(std::path::Path::new("cgroup.events"))?;
        let poll_fd = wait_file.as_raw_fd();
        let mut wait_fd = File::from(wait_file);
        let mut fds = libc::pollfd {
            fd: poll_fd,
            events: libc::POLLPRI | libc::POLLERR,
            revents: 0,
        };
        let mut v = vec![];
        loop {
            v.clear();
            wait_fd
                .seek(std::io::SeekFrom::Start(0))
                .expect("Seek on control group file should succeed");
            wait_fd
                .read_to_end(&mut v)
                .expect("reading from control group should work");
            if v.split(|&c| c == b'\n').any(|line| line == b"populated 0") {
                break;
            }
            // SAFETY: FFI call, valid arguments, fds contains 1 element
            if unsafe { libc::poll(&raw mut fds, 1, -1) } != 1 {
                panic!("poll failed");
            }
        }
        Ok(())
    }

    pub(crate) fn make_child(&mut self, path: &Path) -> Result<(), Errno> {
        assert!(self.exclusive());
        let component = path.as_os_str().as_bytes();
        assert_single_component(component);
        match rustix::fs::mkdirat(
            self.as_fd(),
            path,
            Mode::RUSR
                | Mode::WUSR
                | Mode::XUSR
                | Mode::RGRP
                | Mode::XGRP
                | Mode::ROTH
                | Mode::XOTH,
        ) {
            Ok(()) | Err(Errno::EXIST) => {}
            bad => return bad,
        }
        let p = self.open_sub_cgroup_raw(OFlags::RDONLY | OFlags::DIRECTORY, component)?;
        // exclusive lock on parent acts as exclusive lock on child
        self.fd.push((p, true));
        self.path.push(path);
        Ok(())
    }

    pub(super) fn purge(&mut self, path: &Path) -> Result<(), String> {
        assert!(self.exclusive());
        match rustix::fs::unlinkat(self.as_fd(), Path::new(path), AtFlags::REMOVEDIR) {
            // Trying to purge a deleted cgroup is not an error.
            Ok(()) | Err(Errno::NOENT) => return Ok(()),
            Err(Errno::BUSY) => {}
            Err(e) => return Err(format!("Cannot purge {:?}: {e}", self.joined_path(path))),
        }
        if !self.open_sub_cgroup(path, true, true)? {
            return Ok(());
        }

        rustix::fs::flock(
            self.fd[self.fd.len() - 2].0.as_fd(),
            FlockOperation::LockShared,
        )
        .map_err(|e| format!("Cannot relock {:?}: {e}", self.path.parent()))?;
        self.write_cgroup_value("cgroup.kill", "1")?;
        self.wait_for_empty()
            .map_err(|e| format!("Cannot wait for cgroup to become empty: {e}"))?;
        let fd = self.fd.pop().unwrap().0;
        let v = (|| {
            remove_recursively(fd, 1000)
                .map_err(|e| format!("Cannot remove {:?}: {e}", self.path))?;
            rustix::fs::flock(self.as_fd(), FlockOperation::LockExclusive)
                .map_err(|e| format!("Cannot lock {:?}: {e}", self.path))?;
            match rustix::fs::unlinkat(
                self.as_fd(),
                Path::new(self.path.file_name().unwrap()),
                AtFlags::REMOVEDIR,
            ) {
                // something might have re-created the cgroup in the meantime, which is okay
                Ok(()) | Err(Errno::BUSY) => Ok(()),
                Err(e) => Err(format!("Cannot lock {:?}: {e}", self.path)),
            }
        })();
        assert!(self.path.pop());
        v
    }

    pub(crate) fn write_cgroup_value(&self, name: &str, value: &str) -> Result<(), String> {
        let path = Path::new(name);
        let fd = rustix::fs::openat2(
            self.as_fd(),
            path,
            OFlags::NOATIME | OFlags::CLOEXEC | OFlags::NOFOLLOW | OFlags::WRONLY,
            Mode::empty(),
            ResolveFlags::NO_SYMLINKS | ResolveFlags::BENEATH | ResolveFlags::NO_XDEV,
        )
        .map_err(|e| format!("Cannot open {:?}: {}", self.joined_path(Path::new(name)), e))?;
        File::from(fd).write_all(value.as_bytes()).map_err(|e| {
            format!(
                "Cannot write {:?} to {:?}: {}",
                value,
                self.joined_path(Path::new(name)),
                e
            )
        })
    }
}

fn open_subtree_raw(path: &Path, dirfd: BorrowedFd<'_>) -> Result<OwnedFd, Errno> {
    rustix::fs::openat2(
        dirfd,
        path,
        OFlags::CLOEXEC | OFlags::NOFOLLOW | OFlags::RDONLY,
        Mode::empty(),
        ResolveFlags::NO_SYMLINKS | ResolveFlags::BENEATH | ResolveFlags::NO_XDEV,
    )
}

fn remove_recursively(fd: OwnedFd, remaining_depth: usize) -> Result<(), Errno> {
    if remaining_depth < 1 {
        panic!("control groups too deeply nested");
    }
    let mut d = rustix::fs::Dir::new(fd).expect("cannot start iterating");
    while let Some(element) = d.next() {
        let element = element.expect("Iterating through a cgroup directory failed?");
        if element.file_type() != rustix::fs::FileType::Directory {
            continue;
        }

        let remaining_depth = remaining_depth - 1;
        let d: &rustix::fs::Dir = &d;
        let dirfd = d.fd().unwrap();
        let path = element.file_name();
        remove_all(remaining_depth, dirfd, path)?;
    }
    drop(d);
    Ok(())
}

fn remove_all(
    remaining_depth: usize,
    dirfd: BorrowedFd<'_>,
    path: &std::ffi::CStr,
) -> Result<(), Errno> {
    if path == c"." || path == c".." {
        return Ok(());
    }
    if rustix::fs::unlinkat(dirfd, path, AtFlags::REMOVEDIR).is_ok() {
        return Ok(());
    }
    let fd = rustix::fs::openat2(
        dirfd,
        path,
        OFlags::CLOEXEC | OFlags::NOFOLLOW | OFlags::RDONLY | OFlags::DIRECTORY,
        Mode::empty(),
        ResolveFlags::NO_SYMLINKS | ResolveFlags::BENEATH | ResolveFlags::NO_XDEV,
    )?;
    remove_recursively(fd, remaining_depth)?;
    rustix::fs::unlinkat(dirfd, path, AtFlags::REMOVEDIR)?;
    Ok(())
}
