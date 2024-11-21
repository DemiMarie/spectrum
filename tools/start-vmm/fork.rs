// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>

use std::ffi::c_int;

extern "C" {
    pub fn double_fork() -> c_int;
}
