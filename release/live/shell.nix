# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix (
{ callSpectrumPackage, config, stdenv, btrfs-progs, qemu_kvm }:

let
  efi = callSpectrumPackage ../../host/efi.nix {};
in

(callSpectrumPackage ./. {}).overrideAttrs (
  { nativeBuildInputs ? [], env ? {}, ... }:
  {
    nativeBuildInputs = nativeBuildInputs ++ [ btrfs-progs qemu_kvm ];

    env = env // {
      OVMF_CODE = "${qemu_kvm}/share/qemu/edk2-${stdenv.hostPlatform.qemuArch}-code.fd";
      ROOT_FS = efi.rootfs;
      EFI_IMAGE = efi;
      VERSION = config.version;
    };
  }
)) (_: {})
