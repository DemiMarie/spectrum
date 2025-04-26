# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>

{ run ? ../../vm/app/foot.nix, ... } @ args:

import ../../lib/call-package.nix (
{ callSpectrumPackage, srcOnly
, cloud-hypervisor, crosvm, execline, jq, iproute2, passt, qemu_kvm, reuse, s6
, virtiofsd
}:

(callSpectrumPackage ./. {}).overrideAttrs (
{ nativeBuildInputs ? [], env ? {}, passthru ? {}, ... }:

{
  nativeBuildInputs = nativeBuildInputs ++ [
    cloud-hypervisor crosvm execline jq iproute2 passt qemu_kvm reuse s6
    virtiofsd
  ];

  env = env // {
    CONFIG = callSpectrumPackage run {};

    LINUX_SRC = srcOnly passthru.kernel;
    VMLINUX = "${passthru.kernel.dev}/vmlinux";
  };
})) (_: {}) (removeAttrs args [ "run" ])
