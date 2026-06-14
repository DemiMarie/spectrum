// SPDX-FileCopyrightText: 2026 Demi Marie Obenour <demiobenour@gmail.com>
// SPDX-License-Identifier: EUPL-1.2+

use std::ffi::OsStr;
use std::fs::File;
use std::io::{Read as _, Seek as _, Write as _};
use std::os::unix::prelude::*;

use std::path::{Component, Path, PathBuf};

use rustix::fs::{AtFlags, CWD, Dir, FlockOperation};
use rustix::path;
use rustix::{
    fs::{Mode, OFlags, ResolveFlags},
    io::Errno,
};

pub enum OpenFlags {
    Read,
    Write,
    Directory,
}

#[derive(Debug)]
pub(crate) struct Cgroup {
    fd: Vec<OwnedFd>,
}

impl AsFd for Cgroup {
    fn as_fd(&self) -> BorrowedFd<'_> {
        self.fd.last().unwrap().as_fd()
    }
}

// Wrapper around openat2() with better defaults.
pub fn openat2_simple(
    fd: impl AsFd,
    path: impl path::Arg,
    flags: OpenFlags,
) -> Result<OwnedFd, Errno> {
    rustix::fs::openat2(
        fd.as_fd(),
        path,
        OFlags::CLOEXEC
            | match flags {
                OpenFlags::Read => OFlags::RDONLY | OFlags::NOCTTY,
                OpenFlags::Write => OFlags::WRONLY | OFlags::NOCTTY,
                OpenFlags::Directory => OFlags::RDONLY | OFlags::DIRECTORY,
            },
        Mode::empty(),
        ResolveFlags::NO_SYMLINKS | ResolveFlags::NO_MAGICLINKS | ResolveFlags::NO_XDEV,
    )
}

pub const DEFAULT_LEAF: &str = "$inner.service";

// Remove all subdirectories of the given directory recursively, but not the
// directory itself.
//
// This isn't the most efficient possible algorithm, but simplicity is more
// important than performance in this case.  Also, it keeps open more file
// descriptors than strictly necessary, but Spectrum runs with a very high limit
// for the number of open file descriptors, and it uses shallow control group
// hierarchies.
//
// This uses a recursive algorithm, but so does std::fs::remove_dir_all().  Trying
// to be more robust than the standard library is not worthwhile.  In particular,
// the standard library function must be safe on systems where untrusted users (or
// even network endpoints!) can create deeply nested directory trees, whereas in
// Spectrum cgroups are only writeable by root.
fn remove_recursively(mut dirfd: Dir, remaining_depth: usize) -> Result<(), Errno> {
    if remaining_depth < 1 {
        panic!("control groups too deeply nested");
    }
    while let Some(entry) = dirfd.next() {
        let entry = entry.expect("Iterating through a cgroup directory failed?");
        let name = entry.file_name();
        if entry.file_type() != rustix::fs::FileType::Directory || name == c"." || name == c".." {
            continue;
        }
        let parent_fd = dirfd.fd().unwrap();
        let fd = openat2_simple(parent_fd, name, OpenFlags::Directory)?;
        remove_recursively(Dir::new(fd).unwrap(), remaining_depth - 1)?;
        rustix::fs::unlinkat(parent_fd, name, AtFlags::REMOVEDIR)?;
    }
    Ok(())
}

// Convert the cgroup path to one relative to /sys/fs/cgroup.
//
// If the path starts with /, the leading / is removed and the result is returned
// without further processing.  Otherwise, the current cgroup is read from
// /proc/thread-self/cgroup.  If its last component is $inner.service, that is
// removed.  Finally, the current cgroup is prepended to the provided cgroup path,
// with a single / as separator.  The result of this operation is returned.
fn prepend_current_cgroup_if_needed(path: &Path) -> Result<PathBuf, String> {
    if let Ok(suffix) = path.strip_prefix("/") {
        return Ok(suffix.to_owned());
    }
    // /proc/thread-self is the same as /proc/self, except for the current thread
    // instead of the initial thread.  In this case, the two are identical, but
    // using /proc/thread-self is better practice as it is correct in more cases.
    // Reading /proc/thread-self/cgroup should never fail unless the system is
    // seriously broken.
    let current_cgroup =
        std::fs::read("/proc/thread-self/cgroup").expect("cannot read /proc/thread-self/cgroup");
    // Using this on a system without cgroups v2 mounted is user error
    // and not supported.
    let current_cgroup = current_cgroup
        .strip_prefix(b"0::/")
        .and_then(|e| e.strip_suffix(b"\n"))
        .ok_or_else(|| {
            "/proc/thread-self/cgroup doesn't start with 0::/ or doesn't end with a newline.\n\
            Either cgroups aren't in use at all, or you are using cgroups v1."
                .to_owned()
        })?;
    let mut current_cgroup = PathBuf::from(OsStr::from_bytes(current_cgroup));
    // Strip the implied $inner.service suffix.
    // This is used to satisfy the "no internal processes" rule.
    if current_cgroup.ends_with(Path::new(DEFAULT_LEAF)) {
        assert!(current_cgroup.pop());
    }
    // "." refers to the current cgroup.
    if path != Path::new(".") {
        current_cgroup.push(path);
    }
    Ok(current_cgroup)
}

pub(crate) fn write_value(fd: &dyn AsFd, name: &Path, value: &[u8]) -> Result<(), String> {
    let fd = openat2_simple(fd, name, OpenFlags::Write)
        .map_err(|e| format!("Cannot open {name:?}: {e}"))?;
    File::from(fd).write_all(value).map_err(|e| {
        format!(
            "Cannot write {:?} to {name:?}: {e}",
            OsStr::from_bytes(value)
        )
    })
}

impl Cgroup {
    pub fn new(path: &Path) -> Result<Self, String> {
        let cgroup_root = rustix::fs::openat2(
            CWD,
            Path::new("/sys/fs/cgroup"),
            OFlags::CLOEXEC | OFlags::DIRECTORY | OFlags::RDONLY,
            Mode::empty(),
            ResolveFlags::NO_SYMLINKS | ResolveFlags::NO_MAGICLINKS,
        )
        .map_err(|e| format!("Cannot open /sys/fs/cgroup: {e}"))?;
        // It's simpler to always have the root cgroup at the bottom of the stack,
        // even though no lock needs to be taken on it.  Otherwise, one would need
        // to special-case the cgroup root.  One could remove the first element if
        // there is more than one element in the vector, but that's not worth it.
        // cgroup-setup doesn't operate in an environment where FDs are a limited
        // resource.
        let mut cgroup = Self {
            fd: vec![cgroup_root],
        };

        let path = prepend_current_cgroup_if_needed(path)?;
        for component in path.components() {
            let Component::Normal(component) = component else {
                unreachable!()
            };
            let sub_fd = openat2_simple(&cgroup, component, OpenFlags::Directory)
                .map_err(|e| format!("Cannot open sub-cgroup {component:?}: {e}"))?;
            // Take a shared lock on the cgroup.
            rustix::fs::flock(&sub_fd, FlockOperation::LockShared)
                .map_err(|e| format!("Cannot lock sub-cgroup {component:?}: {e}"))?;
            cgroup.fd.push(sub_fd);
        }
        Ok(cgroup)
    }

    pub fn wait_for_empty(fd: &dyn AsFd) -> std::io::Result<()> {
        let wait_file = openat2_simple(fd, c"cgroup.events", OpenFlags::Read)?;
        let mut wait_fd = File::from(wait_file);
        let mut v = vec![];
        loop {
            v.clear();
            wait_fd
                .seek(std::io::SeekFrom::Start(0))
                .expect("Seek on control group file should succeed");
            wait_fd
                .read_to_end(&mut v)
                .expect("reading from control group should work");
            // Check that the cgroup isn't already empty.  If it was,
            // the kernel would not send an event and poll() would wait
            // forever.
            if v.split(|&c| c == b'\n').any(|line| line == b"populated 0") {
                break;
            }
            let mut fds = libc::pollfd {
                fd: wait_fd.as_raw_fd(),
                events: libc::POLLPRI | libc::POLLERR,
                revents: 0,
            };
            // SAFETY: FFI call, valid arguments, fds contains 1 element
            if unsafe { libc::poll(&raw mut fds, 1, -1) } != 1 {
                panic!("poll failed");
            }
        }
        Ok(())
    }

    pub fn purge_child(&mut self, path: &Path) -> Result<(), String> {
        // See if we can just delete the child directly.
        match rustix::fs::unlinkat(&self, path, AtFlags::REMOVEDIR) {
            // If the cgroup was successfully deleted, or if it
            // has already been deleted, we are done.
            Ok(()) | Err(Errno::NOENT) => return Ok(()),
            // If this cgroup is in use, keep going.
            Err(Errno::BUSY) => {}
            Err(e) => return Err(format!("Cannot purge {path:?}: {e}")),
        }

        let sub_fd = match openat2_simple(&self, path, OpenFlags::Directory) {
            Ok(sub_fd) => sub_fd,
            Err(Errno::NOENT) => return Ok(()),
            Err(e) => {
                return Err(format!("Cannot open sub-cgroup {path:?}: {e}",));
            }
        };

        // Take an exclusive lock on the cgroup that is about to be removed.  This
        // avoids concurrent executions of this program operating on deleted
        // sub-cgroups.
        rustix::fs::flock(&sub_fd, FlockOperation::LockExclusive)
            .map_err(|e| format!("Cannot lock sub-cgroup: {e}"))?;

        // Kill all processes in the child cgroup.
        write_value(&sub_fd, Path::new("cgroup.kill"), b"1")?;

        // Wait for the child cgroup to become empty.
        Self::wait_for_empty(&sub_fd)
            .map_err(|e| format!("Cannot wait for cgroup to become empty: {e}"))?;

        // Remove the child cgroup and its contents recursively.
        remove_recursively(Dir::new(sub_fd).unwrap(), 1000)
            .map_err(|e| format!("Cannot remove: {e}"))?;

        // Delete the cgroup.  If it's been re-created in the meantime and is
        // currently in use, this is not an error.  Another process deleting the
        // cgroup is also not an error.  Both of these can happen because of the
        // time period between remove_child_directories() closing the file
        // descriptor (releasing its lock) and the above call to flock().
        match rustix::fs::unlinkat(&self, path, AtFlags::REMOVEDIR) {
            Ok(()) | Err(Errno::BUSY) | Err(Errno::NOENT) => Ok(()),
            Err(e) => Err(format!("Cannot delete: {e}")),
        }
    }
}
