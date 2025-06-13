# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023, 2025 Alyssa Ross <hi@alyssa.is>

import ../../../lib/call-package.nix (
{ callSpectrumPackage, src, lib, stdenv, runCommand, writeShellScript
, clang-tools, meson, ninja, e2fsprogs, tar2ext4, libressl, qemu_kvm
}:

let
  live = callSpectrumPackage ../../live {};

  ncVm = callSpectrumPackage ../../../vm/make-vm.nix {} {
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
    tar --transform=s,^${ncVm},vms/nc, -Pcvf root.tar ${ncVm}
    tar2ext4 -i root.tar -o $out
    tune2fs -U a7834806-2f82-4faf-8ac4-4f8fd8a474ca $out
  '';
in

stdenv.mkDerivation (finalAttrs: {
  name = "spectrum-integration-tests";

  src = lib.fileset.toSource {
    root = ../../..;
    fileset = lib.fileset.union
      (lib.fileset.intersection src ./.)
      ../../../scripts/run-qemu.sh;
  };
  sourceRoot = "source/release/checks/integration";

  nativeBuildInputs = [ meson ninja ];
  nativeCheckInputs = [ qemu_kvm ];

  mesonFlags = [
    "-Defi=${qemu_kvm}/share/qemu/edk2-${stdenv.hostPlatform.qemuArch}-code.fd"
    "-Dimg=${live}"
    "-Duser_data=${userData}"
  ];

  doCheck = true;
  dontAddTimeoutMultiplier = true;
  mesonCheckFlags = lib.optionals stdenv.hostPlatform.isAarch64 [
    # Tests are run with TCG on aarch64.
    "--timeout-multiplier=15"
  ];

  installPhase = ''
    runHook preInstall
    cp meson-logs/testlog.txt $out
    runHook postInstall
  '';

  shellHook = ''
    unset QEMU_SYSTEM
  '';

  env = {
    QEMU_SYSTEM = "qemu-system-${stdenv.hostPlatform.qemuArch} -nographic";
  };

  passthru.tests = {
    clang-tidy = finalAttrs.finalPackage.overrideAttrs (
      { name, src, nativeBuildInputs ? [], ... }:
      {
        name = "${name}-clang-tidy";

        src = lib.fileset.toSource {
          root = ../../..;
          fileset = lib.fileset.union (lib.fileset.fromSource src) ../../../.clang-tidy;
        };

        nativeBuildInputs = nativeBuildInputs ++ [ clang-tools ];

        buildPhase = ''
          clang-tidy --warnings-as-errors='*' -p . ../*.c ../*.h
          touch $out
          exit 0
        '';
      }
    );
  };
})) (_: {})
