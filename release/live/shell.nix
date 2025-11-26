# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix ({ callSpectrumPackage, stdenv, qemu_kvm, rootfs }:

(callSpectrumPackage ./. {}).overrideAttrs (
  { nativeBuildInputs ? [], env ? {}, ... }:
  {
    nativeBuildInputs = nativeBuildInputs ++ [ qemu_kvm ];

    env = env // {
      OVMF_CODE = "${qemu_kvm}/share/qemu/edk2-${stdenv.hostPlatform.qemuArch}-code.fd";
      ROOT_FS = rootfs;
    };
  }
)) (_: {})
