# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023, 2025 Alyssa Ross <hi@alyssa.is>

import ../../../lib/call-package.nix (
{ callSpectrumPackage, src, lib, stdenv, runCommand, writeShellScript
, clang-tools, jq, meson, ninja, btrfs-progs, glib, libressl, qemu_kvm
}:

let
  live = callSpectrumPackage ../../live {};

  appimage = writeShellScript "test.appimage" ''
    #!/bin/execlineb -P
    echo hello world
  '';

  ncVm = callSpectrumPackage ../../../vm/make-vm.nix {} {
    providers.net = [ "sys.netvm" ];
    type = "nix";
    run = writeShellScript "run" ''
      set -x
      while :; do echo hello | ${libressl.nc}/bin/nc -Nw 2 -6 fd00::2 1234; done
    '';
  };

  portalVm = callSpectrumPackage ../../../vm/make-vm.nix {} {
    type = "nix";
    run = writeShellScript "run" ''
      set -x
      ${lib.getExe' glib "gdbus"} call --session \
          --dest org.freedesktop.portal.Desktop \
          --object-path /org/freedesktop/portal/desktop \
          --method org.freedesktop.portal.FileChooser.OpenFile \
          "" "" '@a{sv} {}' || sleep inf
    '';
  };

  userData = runCommand "user-data.img" {
    nativeBuildInputs = [ btrfs-progs ];
    __structuredAttrs = true;
    unsafeDiscardReferences = { out = true; };
    dontFixup = true;
  } ''
    mkdir -p root/vms
    cp ${appimage} root/test.appimage
    cp -R ${ncVm} root/vms/nc
    cp -R ${portalVm} root/vms/portal
    mkfs.btrfs -U a7834806-2f82-4faf-8ac4-4f8fd8a474ca -r root $out
  '';
in

stdenv.mkDerivation (finalAttrs: {
  name = "spectrum-integration-tests";

  src = lib.fileset.toSource {
    root = ../../..;
    fileset = lib.fileset.union
      (lib.fileset.difference
        (lib.fileset.intersection src ./.)
        (lib.fileset.maybeMissing ./build))
      ../../../scripts/run-qemu.sh;
  };
  sourceRoot = "source/release/checks/integration";

  nativeBuildInputs = [ meson ninja ];
  nativeCheckInputs = [ qemu_kvm ];

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
    EFI_PATH = "${qemu_kvm}/share/qemu/edk2-${stdenv.hostPlatform.qemuArch}-code.fd";
    LIVE_PATH = live;
    USER_DATA_PATH = userData;
  };

  passthru = {
    inherit userData;

    tests = {
      clang-tidy = finalAttrs.finalPackage.overrideAttrs (
        { name, src, nativeBuildInputs ? [], ... }:
        {
          name = "${name}-clang-tidy";

          src = lib.fileset.toSource {
            root = ../../..;
            fileset = lib.fileset.union (lib.fileset.fromSource src) ../../../.clang-tidy;
          };

          nativeBuildInputs = [ clang-tools jq ] ++ nativeBuildInputs;

          buildPhase = ''
            jq -r '.[].file | select(endswith(".c"))' compile_commands.json |
                xargs clang-tidy --warnings-as-errors='*'
            touch $out
            exit 0
          '';
        }
      );
    };
  };
})) (_: {})
