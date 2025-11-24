// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022-2023, 2025 Alyssa Ross <hi@alyssa.is>

use std::ffi::OsString;
use std::io;
use std::os::raw::c_char;
use std::os::unix::prelude::*;
use std::path::{Path, PathBuf};
use std::sync::LazyLock;

use start_vmm::prog_name;

// SAFETY: declaration is compatible with C.
unsafe extern "C" {
    fn mkdtemp(template: *mut c_char) -> *mut c_char;
}

static TMPDIR: LazyLock<PathBuf> = LazyLock::new(|| {
    std::env::var_os("TMPDIR")
        .unwrap_or_else(|| OsString::from("/tmp"))
        .into()
});

pub struct TempDir(PathBuf);

impl TempDir {
    pub fn new() -> std::io::Result<Self> {
        let mut dirname = TMPDIR.clone().into_os_string().into_vec();
        dirname.extend_from_slice(b"/spectrum-start-vmm-test-");
        dirname.extend_from_slice(&prog_name().into_bytes());
        dirname.extend_from_slice(b".XXXXXX\0");

        let c_path = Box::into_raw(dirname.into_boxed_slice());

        // Safe because we own c_path.
        if unsafe { mkdtemp(c_path as *mut c_char) }.is_null() {
            return Err(io::Error::last_os_error());
        }

        // Safe because we own c_path and it came from Box::into_raw.
        let mut buf: Vec<_> = unsafe { Box::from_raw(c_path) }.into();
        buf.pop(); // Remove the NUL terminator.
        let path = PathBuf::from(OsString::from_vec(buf));
        Ok(Self(path))
    }

    pub fn path(&self) -> &Path {
        self.0.as_path()
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
