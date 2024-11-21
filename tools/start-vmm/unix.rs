// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>

use std::ffi::c_int;
use std::io;
use std::os::fd::{AsFd, BorrowedFd};

extern "C" {
    fn clear_cloexec(fd: BorrowedFd) -> c_int;
}

pub trait AsFdExt: AsFd {
    fn clear_cloexec(&self) -> io::Result<()> {
        // SAFETY: trivial.
        match unsafe { clear_cloexec(self.as_fd()) } {
            -1 => Err(io::Error::last_os_error()),
            _ => Ok(()),
        }
    }
}

impl<T: AsFd> AsFdExt for T {}
