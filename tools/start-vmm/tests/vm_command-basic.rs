// SPDX-License-Identifier: EUPL-1.2+
// SPDX-FileCopyrightText: 2022-2024 Alyssa Ross <hi@alyssa.is>

use std::fs::{File, create_dir_all};
use std::path::PathBuf;

use start_vmm::vm_config;
use test_helper::TempDir;

fn main() -> std::io::Result<()> {
    let tmp_dir = TempDir::new()?;

    let vm_dir = tmp_dir.path().join("testvm");
    let kernel_path = vm_dir.join("config/vmlinux");
    let image_path = vm_dir.join("config/blk/root.img");

    create_dir_all(kernel_path.parent().unwrap())?;
    create_dir_all(image_path.parent().unwrap())?;
    File::create(&kernel_path)?;
    File::create(&image_path)?;

    let mut config = vm_config(&vm_dir).unwrap();

    assert_eq!(config.console.mode, "Pty");
    assert_eq!(config.disks.len(), 1);
    let disk1 = config.disks.pop().unwrap();
    assert_eq!(PathBuf::from(disk1.path), image_path);
    assert!(disk1.readonly);
    assert_eq!(config.fs.len(), 1);
    let fs1 = &config.fs[0];
    assert_eq!(fs1.tag, "virtiofs0");
    let expected =
        "/run/service/vm-services/instance/testvm/data/service/vhost-user-fs/env/virtiofsd.sock";
    assert_eq!(fs1.socket, expected);
    assert_eq!(PathBuf::from(config.payload.kernel), kernel_path);
    #[cfg(target_arch = "x86_64")]
    assert_eq!(config.payload.cmdline, "console=ttyS0 root=PARTLABEL=root");
    #[cfg(not(target_arch = "x86_64"))]
    assert_eq!(config.payload.cmdline, "root=PARTLABEL=root");
    assert_eq!(config.memory.size, 0x40000000);
    assert!(config.memory.shared);
    assert_eq!(config.serial.mode, "File");
    assert_eq!(config.serial.file.unwrap(), "/run/testvm.log");
    assert_eq!(config.vsock.cid, 3);
    assert_eq!(PathBuf::from(config.vsock.socket), vm_dir.join("vsock"));

    Ok(())
}
