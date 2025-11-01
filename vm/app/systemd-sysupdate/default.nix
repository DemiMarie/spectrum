# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

import ../../../lib/call-package.nix (
{ callSpectrumPackage, curl, lib, src
, runCommand, systemd, writeScript
}:

let
  mountpoint = "/run/virtiofs/virtiofs0";
in

callSpectrumPackage ../../make-vm.nix {} {
  providers.net = [ "sys.netvm" ];
  type = "nix";
  run = builtins.path {
    name = "run-update";
    path = ./run-update;
  };
}) (_: {})
