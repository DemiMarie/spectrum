# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

import ../lib/call-package.nix (
{ callSpectrumPackage, config, efi
, runCommand, stdenv, rootfs
}:

runCommand "spectrum-update-directory" {
  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
  dontFixup = true;
  env = {
    VERSION = config.version;
    ROOTHASH = "${rootfs}/rootfs.verity.roothash";
    VERITY = "${rootfs}/rootfs.verity.superblock";
    ROOT_FS = "${rootfs}/rootfs";
    EFI = efi;
  };
} ''
  read -r roothash < "$ROOTHASH"
  mkdir -- "$out"
  cp -- "$VERITY" "$out/Spectrum_$VERSION.verity"
  cp -- "$ROOT_FS" "$out/Spectrum_$VERSION.root"
  cp -- "$EFI" "$out/Spectrum_$VERSION.efi"
  cd -- "$out"
  sha256sum -b "Spectrum_$VERSION.root" "Spectrum_$VERSION.verity" "Spectrum_$VERSION.efi" > SHA256SUMS
  ''
) (_: {})
