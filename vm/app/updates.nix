# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix (
{ callSpectrumPackage, lib, pkgsMusl, pkgsStatic, src, writeScript, systemd }:

pkgsMusl.callPackage (
{ stdenvNoCC, curl }:

pkgsStatic.callPackage (
{ execline, runCommand }:

let
  raw_update_url = builtins.readFile ../../update-url;
  update-url =
    if builtins.match "^https?://([[:alnum:]:./?=~-]|%[[:xdigit:]]{2})+/\n$" raw_update_url == null then
      builtins.abort "Bad update URL"
    else
      builtins.substring 0 (builtins.stringLength raw_update_url - 1) raw_update_url;
  sysupdate-d = stdenvNoCC.mkDerivation {
    name = "spectrum-systemd-transfer-files";
    src = ./.;
    installPhase =
      ''
      mkdir -- "$out"
      (
        cd -- "$src" &&
        for i in sysupdate.d/*.transfer; do
          s=''${i#sysupdate.d/} &&
          sed 's,@UPDATE_URL@,${update-url},g' < "$i" > "$out/$s" || exit
        done
        printf %s\\n '${update-url}' > "$out/update-url"
      ) || exit
      '';
  };
  l = lib.escapeShellArgs;
  mountpoint = "/run/virtiofs/virtiofs0/user";
  sysupdate-path = "${systemd}/lib/systemd/systemd-sysupdate";
  runner = writeScript "update-run-script" (
    "#!/bin/sh --\n" +
    builtins.concatStringsSep " && \\\n" [
      (l ["mount" "-toverlay" "-olowerdir=${mountpoint}/etc:/etc" "--" "overlay" "/etc"])
      (l [sysupdate-path "--definitions=${sysupdate-d}" "update"])
      (l ["${curl}/bin/curl" "-L" "--proto" "=http,https"
          "-o" "${mountpoint}/update-destination/SHA256SUMS.gpg"
          "--" "${update-url}SHA256SUMS.gpg"])
      (l ["${curl}/bin/curl" "-L" "--proto" "=http,https"
          "-o" "${mountpoint}/update-destination/SHA256SUMS"
          "--" "${update-url}/SHA256SUMS"])
    ]);
in

callSpectrumPackage ../make-vm.nix {} {
  providers.net = [ "sys.netvm" ];
  type = "nix";
  run = "${runner}";
}) {}) {}) (_: {})
