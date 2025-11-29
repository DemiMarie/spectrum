# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

import ../../../lib/call-package.nix (
{ callSpectrumPackage, curl, lib, src
, runCommand, systemd, writeScript
}:

let
  downloadUpdate = builtins.path {
    name = "download-update";
    path = ./download-update;
  };
in

callSpectrumPackage ../../make-vm.nix {} {
  providers.net = [ "sys.netvm" ];
  type = "nix";
  run = writeScript "run-script" ''
    #!/usr/bin/execlineb -WS0
    export CURL_PATH ${curl}/bin/curl
    export SYSTEMD_SYSUPDATE_PATH ${systemd}/lib/systemd/systemd-sysupdate
    ${downloadUpdate}
  '';
}) (_: {})
