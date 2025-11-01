# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

import ../lib/call-package.nix (
{ callSpectrumPackage, config, runCommand, stdenv }:

let
  efi = import ../host/efi.nix {};
in
runCommand "spectrum-update-directory" {
  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
  dontFixup = true;
  env = { VERSION = config.version; };
} ''
  mkdir -- "$out"
  cd -- "$out"
  read -r roothash < ${efi.rootfs}/rootfs.verity.roothash
  [[ "$roothash" =~ ^[0-9a-f]{64}$ ]]
  cp -- ${efi}/"Spectrum_$VERSION.efi" "Spectrum_$VERSION.efi"
  cp -- ${efi.rootfs}/rootfs.verity.superblock "Spectrum_$VERSION_''${roothash:32:32}.verity"
  cp -- ${efi.rootfs}/rootfs "Spectrum_$VERSION_''${roothash:0:32}.rootfs"
  sha256sum "Spectrum_$VERSION.efi" \
    "Spectrum_$VERSION_''${roothash:32:32}.verity" \
    "Spectrum_$VERSION_''${roothash:0:32}.rootfs" > SHA256SUMS
  ''
) (_: {})
