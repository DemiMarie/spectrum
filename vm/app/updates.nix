# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix (
{ callSpectrumPackage, lib }:

let
  sysupdate-d = stdenvNoCC.mkDerivation {
    name = "spectrum-systemd-transfer-files";
    src = fileset.toSource ./sysupdate.d;
    buildPhase = ''
      cp -a -t "$out" -- sysupdate.d/*.transfer
    '';
  };

  updater = stdenvNoCC.mkDerivation {
    name = "spectrum-updater";
    buildInputs = [
      execline
      systemdMinimal
      update_dependencies;
    ];

    buildPhase = ''
printf '#!/bin/sh --
set -eu
exec systemd-sysupdate --definitions=%s\n' ${
# First level of escaping is for the build process.
# The second level is for the generated script.
lib.escapeShellArg (lib.escapeShellArg sysupdate-d)} > "$out/run"
    ''
  };
in

callSpectrumPackage ../make-vm.nix {} {
  providers.net = [ "sys.netvm" ];
  type = "nix";
  run = "${updater}/run";
}) (_: {})
