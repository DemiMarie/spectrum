# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2022, 2024 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix (
{ callSpectrumPackage, rootfs, pkgsStatic, stdenv
, cryptsetup, jq, qemu_kvm, tar2ext4, util-linux
, config
}:

let
  initramfs = callSpectrumPackage ./. {};
in

initramfs.overrideAttrs ({ nativeBuildInputs ? [], env ? {}, ... }: {
  nativeBuildInputs = nativeBuildInputs ++ [
    cryptsetup jq qemu_kvm tar2ext4 util-linux
  ];

  env = env // {
    KERNEL = "${rootfs.kernel}/${stdenv.hostPlatform.linux-kernel.target}";
    ROOT_FS_DIR = rootfs;
    VERSION = config.version;
  };
})) (_: {})
