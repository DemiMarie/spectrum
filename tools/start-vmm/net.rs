// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022-2024 Alyssa Ross <hi@alyssa.is>

use std::borrow::Cow;
use std::fmt::{self, Display, Formatter};
use std::path::Path;

use miniserde::ser::Fragment;
use miniserde::Serialize;

use crate::ch::NetConfigC;

#[repr(transparent)]
#[derive(Copy, Clone)]
pub struct MacAddress([u8; 6]);

impl MacAddress {
    pub fn new(octets: [u8; 6]) -> Self {
        Self(octets)
    }
}

impl Display for MacAddress {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        write!(
            f,
            "{:02X}:{:02X}:{:02X}:{:02X}:{:02X}:{:02X}",
            self.0[0], self.0[1], self.0[2], self.0[3], self.0[4], self.0[5]
        )
    }
}

impl Serialize for MacAddress {
    fn begin(&self) -> Fragment {
        Fragment::Str(Cow::Owned(self.to_string()))
    }
}

extern "C" {
    /// # Safety
    ///
    /// The rest of the result is only valid if the returned fd is not -1.
    // SAFETY: &Path is sized, so it's okay to pass a reference to it
    // to C, as long as it's opaque to C.
    #[allow(improper_ctypes)]
    pub fn net_setup(provider_vm_dir: &&Path) -> NetConfigC;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mac_to_string_all_zero() {
        assert_eq!(MacAddress([0; 6]).to_string(), "00:00:00:00:00:00");
    }

    #[test]
    fn mac_to_string_hex() {
        let mac = MacAddress([0xFE, 0xDC, 0xBA, 0x98, 0x76, 0x54]);
        assert_eq!(mac.to_string(), "FE:DC:BA:98:76:54");
    }
}
