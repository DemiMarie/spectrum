// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022-2023 Alyssa Ross <hi@alyssa.is>

use std::collections::BTreeSet;
use std::fs::{create_dir, create_dir_all, File};
use std::os::unix::fs::symlink;
use std::path::PathBuf;

use start_vmm::vm_config;
use test_helper::TempDir;

fn main() -> std::io::Result<()> {
    let tmp_dir = TempDir::new()?;

    let vm_config_dir = tmp_dir.path().join("testvm/config");

    create_dir_all(&vm_config_dir)?;
    File::create(vm_config_dir.join("vmlinux"))?;
    create_dir(vm_config_dir.join("blk"))?;

    let image_paths: BTreeSet<_> = (1..=2)
        .map(|n| vm_config_dir.join(format!("blk/disk{n}.img")))
        .collect();

    for image_path in &image_paths {
        symlink("/dev/null", image_path)?;
    }

    let config = vm_config(vm_config_dir.parent().unwrap()).unwrap();
    assert_eq!(config.disks.len(), 2);
    assert!(config.disks.iter().all(|disk| disk.readonly));

    let actual_paths: BTreeSet<_> = config
        .disks
        .into_iter()
        .map(|disk| PathBuf::from(disk.path))
        .collect();

    assert_eq!(actual_paths, image_paths);

    Ok(())
}
