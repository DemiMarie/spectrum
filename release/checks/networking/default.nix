# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023, 2025 Alyssa Ross <hi@alyssa.is>

import ../../../lib/call-package.nix (
{ callSpectrumPackage, lib, stdenv, runCommand, runCommandCC, writeShellScript
, clang-tools, e2fsprogs, tar2ext4, libressl, qemu_kvm
}:

let
  live = callSpectrumPackage ../../live {};

  vm = callSpectrumPackage ../../../vm/make-vm.nix {} {
    providers.net = [ "sys.netvm" ];
    type = "nix";
    run = writeShellScript "run" ''
      set -x
      while ! echo hello | ${libressl.nc}/bin/nc -N 10.0.2.2 1234; do :; done
    '';
  };

  userData = runCommand "user-data.img" {
    nativeBuildInputs = [ e2fsprogs tar2ext4 ];
  } ''
    tar --transform=s,^${vm},vms/vm, -Pcvf root.tar ${vm}
    tar2ext4 -i root.tar -o $out
    tune2fs -U a7834806-2f82-4faf-8ac4-4f8fd8a474ca $out
  '';

  cflags = [ "-std=c23" "-D_GNU_SOURCE" ];

  test = runCommandCC "test" {} ''
    $CC -o $out ${lib.escapeShellArgs cflags} ${./test.c}
  '';

  testScript = writeShellScript "spectrum-networking-test" ''
    PATH=${lib.escapeShellArg (lib.makeBinPath [ qemu_kvm ])}:"$PATH"
    exec ${test} \
        ${../../../scripts/run-qemu.sh} \
        ${qemu_kvm}/share/qemu/edk2-${stdenv.hostPlatform.qemuArch}-code.fd \
        ${live} \
        ${userData}
  '';
in

runCommand "run-${testScript.name}" {
  inherit testScript userData;

  passthru.tests = {
    clang-tidy = runCommand "run-${testScript.name}-clang-tidy" {
      nativeBuildInputs = [ clang-tools ];
    } ''
      clang-tidy --config-file=${../../../.clang-tidy} --warnings-as-errors='*' \
          ${lib.escapeShellArgs (map (flag: "--extra-arg=${flag}") cflags)} \
          ${./test.c}
      touch $out
    '';
  };
} ''
  export QEMU_SYSTEM='qemu-system-${stdenv.hostPlatform.qemuArch} -nographic'
  $testScript
  touch $out
'') (_: {})
