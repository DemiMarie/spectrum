# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

import ../../lib/call-package.nix (
{ callSpectrumPackage, config, curl, lib, src
, runCommand, systemd, writeScript
}:

let
  update-url = config.update-url;
  mountpoint = "/run/virtiofs/virtiofs0";
  sysupdate-path = "${systemd}/lib/systemd/systemd-sysupdate";
  runner = writeScript "update-run-script"
    ''
    #!/usr/bin/execlineb -P
    if { mount -toverlay -olowerdir=${mountpoint}/etc:/etc -- overlay /etc }
    envfile ${mountpoint}/etc/url-env
    importas -i update_url UPDATE_URL
    if { ${sysupdate-path} update }
    if { ${curl}/bin/curl -L --proto =http,https
       -o ${mountpoint}/updates/SHA256SUMS.gpg ''${update_url}/SHA256SUMS.gpg }
    # systemd-sysupdate recently went from needing SHA256SUMS.gpg to SHA256SUMS.sha256.asc.
    # I (Demi) have no need if this is intentional or a bug.  I also have no idea if this
    # behavior will stay unchanged in the future.  Therefore, create both files and let
    # systemd-sysupdate ignore the one it isn't interested in.
    if { ln -f ${mountpoint}/updates/SHA256SUMS.gpg ${mountpoint}/updates/SHA256SUMS.sha256.asc }
    ${curl}/bin/curl -L --proto =http,https
       -o ${mountpoint}/updates/SHA256SUMS ''${update_url}/SHA256SUMS
    '';
in

callSpectrumPackage ../make-vm.nix {} {
  providers.net = [ "sys.netvm" ];
  type = "nix";
  run = "${runner}";
}) (_: {})
