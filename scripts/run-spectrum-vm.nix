# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>

{ run ? ../vm/app/poweroff.nix, ... } @ args:

import ../lib/call-package.nix (
{ callSpectrumPackage, start-vm
, lib, runCommand, runCommandCC, clang-tools, cloud-hypervisor, virtiofsd
}:

let
  cflags = [
    ''-D_GNU_SOURCE''
    ''-DAPPVM_PATH="${callSpectrumPackage ../img/app {}}"''
    ''-DCONFIG_PATH="${callSpectrumPackage run {}}"''
    ''-DCLOUD_HYPERVISOR_PATH="${lib.getExe cloud-hypervisor}"''
    ''-DSTART_VM_PATH="${lib.getExe start-vm}"''
    ''-DVIRTIOFSD_PATH="${lib.getExe virtiofsd}"''
  ];
in

runCommandCC "run-spectrum-vm" {
  passthru.tests = {
    clang-tidy = runCommand "run-spectrum-vm-clang-tidy" {
      nativeBuildInputs = [ clang-tools ];
    } ''
      clang-tidy --warnings-as-errors='*' \
          ${lib.escapeShellArgs (map (flag: "--extra-arg=${flag}") cflags)} \
          ${./run-spectrum-vm.c}
      touch $out
    '';
  };
} ''
  $CC -o $out ${lib.escapeShellArgs cflags} -Wall -Wpedantic \
      ${./run-spectrum-vm.c}
'') (_: {}) (removeAttrs args [ "run" ])
