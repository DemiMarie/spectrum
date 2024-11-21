// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2024 Alyssa Ross <hi@alyssa.is>

use std::borrow::Cow;
use std::cmp::max;
use std::env::args_os;
use std::ffi::{OsStr, OsString};
use std::fs::read_dir;
use std::io::{self, stdout, Write};
use std::os::unix::prelude::*;
use std::path::Path;
use std::process::{exit, Command, Stdio};
use std::str;

use miniserde::{json, Deserialize};

fn prog_name() -> String {
    args_os()
        .next()
        .as_ref()
        .map(Path::new)
        .and_then(Path::file_name)
        .map(OsStr::to_string_lossy)
        .unwrap_or(Cow::Borrowed("lsvm"))
        .into_owned()
}

struct Vm {
    id: OsString,
    running: Option<bool>,
}

fn vm_running(id: &OsStr) -> Result<bool, String> {
    #[derive(Deserialize)]
    struct Info {
        state: String,
    }

    let output = Command::new("ch-remote")
        .arg("--api-socket")
        .arg(Path::new("/run/vm").join(id).join("vmm"))
        .arg("info")
        .stderr(Stdio::inherit())
        .output()
        .map_err(|e| format!("running ch-remote: {e}"))?;

    if !output.status.success() {
        return Err("ch-remote failed".to_string());
    }

    let json =
        str::from_utf8(&output.stdout).map_err(|e| format!("parsing ch-remote output: {e}"))?;
    let Info { state } =
        json::from_str(json).map_err(|e| format!("parsing ch-remote output: {e}"))?;

    Ok(state != "Created")
}

fn write_vm(mut out: impl Write, name_col_len: usize, vm: &Vm) -> io::Result<()> {
    let id = vm.id.as_bytes();

    out.write_all(id)?;
    write!(out, "{:1$}", "", name_col_len - id.len())?;

    match vm.running {
        Some(true) => writeln!(out, "\x1B[32;1mRUNNING\x1B[0m"),
        Some(false) => writeln!(out, "\x1B[31mSTOPPED\x1B[0m"),
        None => writeln!(out, "\x1B[33mUNKNOWN\x1B[0m"),
    }
}

fn run() -> Result<(), String> {
    let mut ids = Vec::new();

    for entry in read_dir("/run/vm").map_err(|e| format!("reading /run/vm: {e}"))? {
        let id = entry
            .map_err(|e| format!("iterating /run/vm: {e}"))?
            .file_name();
        ids.push(id);
    }

    let mut stdout = stdout();

    let name_col_len = max(ids.iter().map(|s| s.len()).max().unwrap_or(0), 4) + 2;

    writeln!(stdout, "{:name_col_len$}STATUS", "NAME")
        .map_err(|e| format!("writing output: {e}"))?;

    for id in ids {
        let running = vm_running(&id)
            .inspect_err(|e| eprintln!("{}: getting state of {:?}: {e}", prog_name(), id))
            .ok();

        let vm = Vm { running, id };

        write_vm(&mut stdout, name_col_len, &vm).map_err(|e| format!("writing output: {e}"))?;
    }

    Ok(())
}

fn main() {
    if let Err(e) = run() {
        eprintln!("{}: {}", prog_name(), e);
        exit(1);
    }
}
