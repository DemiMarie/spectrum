# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021, 2023-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie

import ../../lib/call-package.nix (
{ callSpectrumPackage, rootfs, pkgsStatic, srcOnly, stdenv
, btrfs-progs, cryptsetup, jq, netcat, qemu_kvm, reuse, util-linux
, verity
}:

rootfs.overrideAttrs (
{ passthru ? {}, nativeBuildInputs ? [], env ? {}, ... }:

{
  nativeBuildInputs = nativeBuildInputs ++ [
    btrfs-progs cryptsetup jq netcat qemu_kvm reuse util-linux
  ];

  env = env // {
    INITRAMFS = callSpectrumPackage ../initramfs {};
    KERNEL = "${passthru.kernel}/${stdenv.hostPlatform.linux-kernel.target}";
    LINUX_SRC = srcOnly passthru.kernel;
    VMLINUX = "${passthru.kernel.dev}/vmlinux";
    ROOT_FS_VERITY = "${verity}/rootfs.verity.superblock";
    ROOT_FS_VERITY_ROOTHASH = "${verity}/rootfs.verity.roothash";
  };
})) (_: {})
