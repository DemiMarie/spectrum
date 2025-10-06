// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>

use std::fs::File;
use std::io::Write as _;

pub fn notify_readiness(mut fd: File) -> Result<(), String> {
    writeln!(fd).map_err(|e| format!("notifying readiness: {e}"))
}
