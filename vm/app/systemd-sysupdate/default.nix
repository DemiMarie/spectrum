# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

import ../../../lib/call-package.nix (
{ callSpectrumPackage, curl, lib, src
, runCommand, systemd, writeScript
}:

let
  escape-url = builtins.path {
    name = "escape-url";
    path = ./escape-url.awk;
  };
  populate-transfer-directory = builtins.path {
    name = "populate-transfer-directory";
    path = ./populate-transfer-directory;
  };
in

callSpectrumPackage ../../make-vm.nix {} {
  providers.net = [ "sys.netvm" ];
  type = "nix";
  run = writeScript "run-script" ''
#!/usr/bin/execlineb -P
export LC_ALL C
export LANGUAGE C
if { mount -toverlay -olowerdir=/run/virtiofs/virtiofs0/etc:/etc -- overlay /etc }
backtick tmpdir { mktemp -d /run/sysupdate-XXXXXX }
# Not a useless use of cat: if there are NUL bytes in the URL
# busybox's awk might misbehave.
backtick update_url { cat /etc/update-url }
# Leading and trailing whitespace is almost certainly user error,
# but be friendly to the user (by stripping it) rather than failing.
backtick update_url {
  awk "BEGIN {
    url = ENVIRON[\"update_url\"]
    gsub(/^[[:space:]]+/, \"\", url)
    gsub(/[[:space:]]+$/, \"\", url)
    print url
  }"
}
multisubstitute {
  importas -iSu tmpdir
  importas -iSu update_url
}
if { ${populate-transfer-directory} ${escape-url} /etc/vm-sysupdate.d ''${tmpdir} ''${update_url} }
if { ${systemd}/lib/systemd/systemd-sysupdate --definitions=''${tmpdir} update }
# [ and ] are allowed in update URLs so that IPv6 addresses work, but
# they cause globbing in the curl command-line tool by default.  Use --globoff
# to disable this feature.  Only allow HTTP and HTTPS protocols on redirection.
if { ${curl}/bin/curl -L --proto-redir =http,https --globoff
     -o /run/virtiofs/virtiofs0/updates/SHA256SUMS -- ''${update_url}/SHA256SUMS }
${curl}/bin/curl -L --proto-redir =http,https --globoff
     -o /run/virtiofs/virtiofs0/updates/SHA256SUMS.sha256.asc -- ''${update_url}/SHA256SUMS.sha256.asc
'';
}) (_: {})
