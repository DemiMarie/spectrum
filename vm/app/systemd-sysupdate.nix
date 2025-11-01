# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

import ../../lib/call-package.nix (
{ callSpectrumPackage, curl, lib, src
, runCommand, systemd, writeScript
}:

let
  mountpoint = "/run/virtiofs/virtiofs0";
in

callSpectrumPackage ../make-vm.nix {} {
  providers.net = [ "sys.netvm" ];
  type = "nix";
  run = writeScript "update-run-script"
    ''
    #!/usr/bin/execlineb -P
    if { mount -toverlay -olowerdir=${mountpoint}/etc:/etc -- overlay /etc }
    envfile ${mountpoint}/etc/url-env
    importas -i update_url UPDATE_URL
    if { ${systemd}/lib/systemd/systemd-sysupdate update }
    # [ and ] are allowed in update URLs so that IPv6 addresses work, but
    # they cause globbing in the curl command-line tool by default.  Use --globoff
    # to disable this feature.  Only allow HTTP and HTTPS protocols.
    if { ${curl}/bin/curl -L --proto =http,https --proto-redir =http,https --globoff
         -o ${mountpoint}/updates/SHA256SUMS ''${update_url}/SHA256SUMS }
    if { ${curl}/bin/curl -L --proto =http,https --proto-redir =http,https --globoff
         -o ${mountpoint}/updates/SHA256SUMS.gpg ''${update_url}/SHA256SUMS.gpg }
    # systemd-sysupdate recently went from needing SHA256SUMS.gpg to SHA256SUMS.sha256.asc.
    # This is <https://github.com/systemd/systemd/issues/39723>.
    # Until this is resolved, create both files and let
    # systemd-sysupdate ignore the one it isn't interested in.
    ln -f ${mountpoint}/updates/SHA256SUMS.gpg ${mountpoint}/updates/SHA256SUMS.sha256.asc
    '';
}) (_: {})
