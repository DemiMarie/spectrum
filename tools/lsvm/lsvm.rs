// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2024 Alyssa Ross <hi@alyssa.is>

use std::borrow::Cow;
use std::collections::HashMap;
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
        .map_or(Cow::Borrowed("lsvm"), OsStr::to_string_lossy)
        .into_owned()
}

struct Vm {
    id: OsString,
    names: Vec<OsString>,
    running: Option<bool>,
}

fn vm_running(id: &OsStr) -> Result<bool, String> {
    #[derive(Deserialize)]
    struct Info {
        state: String,
    }

    let output = Command::new("ch-remote")
        .arg("--api-socket")
        .arg(Path::new("/run/vm/by-id").join(id).join("vmm"))
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

fn write_vm(mut out: impl Write, vm: &Vm) -> io::Result<()> {
    out.write_all(vm.id.as_bytes())?;

    match vm.running {
        Some(true) => write!(out, " \x1B[32;1mRUNNING\x1B[0m ")?,
        Some(false) => write!(out, " \x1B[31mSTOPPED\x1B[0m ")?,
        None => write!(out, " \x1B[33mUNKNOWN\x1B[0m ")?,
    }

    out.write_all(
        &vm.names
            .iter()
            .map(|n| n.as_bytes())
            .collect::<Vec<_>>()
            .join(&b" "[..]),
    )?;

    writeln!(out)
}

fn run() -> Result<(), String> {
    let mut names = HashMap::new();

    for entry in read_dir("/run/vm/by-id").map_err(|e| format!("reading /run/vm/by-id: {e}"))? {
        let entry = entry.map_err(|e| format!("iterating /run/vm/by-id: {e}"))?;
        if entry
            .file_type()
            .map_err(|e| format!("getting type of {:?}: {e}", entry.path()))?
            .is_dir()
            && entry.file_name() != "by-name"
        {
            names.insert(entry.file_name(), Vec::new());
        }
    }

    for entry in read_dir("/run/vm/by-name").map_err(|e| format!("reading /run/vm/by-name: {e}"))? {
        let entry = entry.map_err(|e| format!("iterating /run/vm/by-name: {e}"))?;
        let target = entry
            .path()
            .read_link()
            .map_err(|e| format!("readlink {:?}: {e}", entry.path()))?;
        let vm = target
            .file_name()
            .ok_or_else(|| format!("target of {:?} has no name", entry.path()))?;

        names
            .get_mut(vm)
            .ok_or_else(|| format!("{:?} links to non-existent VM {:?}", entry.path(), vm))?
            .push(entry.file_name());
    }

    let mut stdout = stdout();

    writeln!(stdout, "ID     STATUS  NAMES").map_err(|e| format!("writing output: {e}"))?;

    for (id, names) in names {
        let running = vm_running(&id)
            .inspect_err(|e| eprintln!("{}: getting state of {:?}: {e}", prog_name(), id))
            .ok();

        let vm = Vm { running, id, names };

        write_vm(&mut stdout, &vm).map_err(|e| format!("writing output: {e}"))?;
    }

    Ok(())
}

fn main() {
    if let Err(e) = run() {
        eprintln!("{}: {}", prog_name(), e);
        exit(1);
    }
}
