# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021, 2023-2024 Alyssa Ross <hi@alyssa.is>

import ../../../lib/call-package.nix (
{ callSpectrumPackage, srcOnly
, cloud-hypervisor, crosvm, execline, jq, iproute2, qemu_kvm, passt, reuse, s6
}:

(callSpectrumPackage ./. {}).overrideAttrs (
{ nativeBuildInputs ? [], env ? {}, passthru ? {}, ... }:

{
  nativeBuildInputs = nativeBuildInputs ++ [
    cloud-hypervisor crosvm execline jq iproute2 qemu_kvm passt reuse
    s6
  ];

  env = env // {
    LINUX_SRC = srcOnly passthru.kernel.configfile;
    VMLINUX = "${passthru.kernel.dev}/vmlinux";
  };
})) (_: {})
