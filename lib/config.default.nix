# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

{
  pkgsFun = import ./nixpkgs.default.nix;
  pkgsArgs = {};
  version = "0.0.0";
  update-url = "https://your-spectrum-os-update-server.invalid/download-directory";
  update-signing-key = ./fake-update-signing-key.gpg;
}
