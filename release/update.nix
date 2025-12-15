# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

import ../lib/call-package.nix (
{ callSpectrumPackage, config, runCommand, stdenv }:

let
  efi = callSpectrumPackage ../host/efi.nix {};
in
runCommand "spectrum-update-directory" {
  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
  dontFixup = true;
  env = { VERSION = config.version; };
} ''
  # stdenv sets -eo pipefail, but not -u
  set -u
  mkdir -- "$out"
  cd -- "$out"
  read -r roothash < ${efi.rootfs}/rootfs.verity.roothash
  if ! [[ "$roothash" =~ ^[0-9a-f]{64}$ ]]; then
    printf 'Internal error: bad root hash %q\n' "$roothash"
    exit 1
  fi
  cp -- ${efi} "Spectrum_$VERSION.efi"
  cp -- ${efi.rootfs}/rootfs.verity.superblock "Spectrum_''${VERSION}_''${roothash:32:32}.verity"
  cp -- ${efi.rootfs}/rootfs "Spectrum_''${VERSION}_''${roothash:0:32}.root"
  sha256sum -b "Spectrum_$VERSION.efi" \
    "Spectrum_''${VERSION}_''${roothash:32:32}.verity" \
    "Spectrum_''${VERSION}_''${roothash:0:32}.root" > SHA256SUMS
  ''
) (_: {})
