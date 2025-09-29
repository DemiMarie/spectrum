# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021, 2023-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie

import ../../lib/call-package.nix (
{ callSpectrumPackage, rootfs, srcOnly, stdenv
, btrfs-progs, cryptsetup, jq, netcat, qemu_kvm, reuse, util-linux
, fakeroot
}:

rootfs.overrideAttrs (
{ passthru ? {}, nativeBuildInputs ? [], env ? {}, ... }:

{
  nativeBuildInputs = nativeBuildInputs ++ [
    btrfs-progs cryptsetup jq netcat qemu_kvm reuse util-linux fakeroot
  ];

  env = env // {
    INITRAMFS = callSpectrumPackage ../initramfs {};
    KERNEL = "${passthru.kernel}/${stdenv.hostPlatform.linux-kernel.target}";
    LINUX_SRC = srcOnly passthru.kernel;
    VMLINUX = "${passthru.kernel.dev}/vmlinux";
  };
})) (_: {})
