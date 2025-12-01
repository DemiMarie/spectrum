// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

use std::fs::File;
use std::io::read_to_string;

use crate::keyfile::parse;

pub fn extract_runtime(mut metadata: File) -> Result<String, String> {
    let metadata = read_to_string(&mut metadata).map_err(|e| e.to_string())?;
    let group = parse(&metadata).map_err(|e| e.to_string())?;
    let application = group
        .get("Application")
        .ok_or_else(|| "Application group missing".to_string())?;
    Ok(application
        .get("runtime")
        .ok_or_else(|| "runtime property missing".to_string())?
        .clone())
}
