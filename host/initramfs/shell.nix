# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2022, 2024 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix (
{ callSpectrumPackage, rootfs, pkgsStatic, stdenv
, cryptsetup, qemu_kvm, tar2ext4, util-linux
}:

let
  extfs = pkgsStatic.callPackage ./extfs.nix { };
  initramfs = callSpectrumPackage ./. {};
in

initramfs.overrideAttrs ({ nativeBuildInputs ? [], env ? {}, ... }: {
  nativeBuildInputs = nativeBuildInputs ++ [
    cryptsetup qemu_kvm tar2ext4 util-linux
  ];

  env = env // {
    EXT_FS = extfs;
    KERNEL = "${rootfs.kernel}/${stdenv.hostPlatform.linux-kernel.target}";
    ROOT_FS = rootfs;
  };
})) (_: {})
