# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2022 Unikie

import ../../lib/call-package.nix (
{ callSpectrumPackage, lib, writeScript, gnome-text-editor }:

callSpectrumPackage ../make-vm.nix {} {
  type = "nix";
  run = writeScript "run-gnome-text-editor" ''
    #!/bin/execlineb -WP
    export GDK_DEBUG portals
    ${lib.getExe gnome-text-editor}
  '';
}) (_: {})
