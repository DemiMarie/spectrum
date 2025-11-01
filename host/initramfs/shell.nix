# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2022, 2024 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix (
{ callSpectrumPackage, rootfs, pkgsStatic, stdenv
, cryptsetup, qemu_kvm, tar2ext4, util-linux, verity
, jq
}:

let
  initramfs = callSpectrumPackage ./. {};
in

initramfs.overrideAttrs ({ nativeBuildInputs ? [], env ? {}, ... }: {
  nativeBuildInputs = nativeBuildInputs ++ [
    cryptsetup qemu_kvm tar2ext4 util-linux jq
  ];

  env = env // {
    KERNEL = "${rootfs.kernel}/${stdenv.hostPlatform.linux-kernel.target}";
    ROOT_FS = rootfs;
    ROOT_FS_VERITY = "${verity}/rootfs.verity.superblock";
    ROOT_FS_VERITY_ROOTHASH = "${verity}/rootfs.verity.roothash";
    VERSION = import ../../lib/version.nix;
  };
})) (_: {})
