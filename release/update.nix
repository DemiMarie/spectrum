# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

import ../lib/call-package.nix (
{ bash, callSpectrumPackage, cryptsetup, runCommand
, stdenv, systemdUkify, rootfs, verity, efi
}:
let
  initramfs = callSpectrumPackage ./initramfs {};
  version = import ../lib/version.nix;
  efiArch = stdenv.hostPlatform.efiArch;
  kernel = "${rootfs.kernel}/${stdenv.hostPlatform.linux-kernel.target}";
  systemd = systemdUkify.overrideAttrs ({ mesonFlags ? [], ... }: {
    # The default limit is too low to build a generic aarch64 distro image:
    # https://github.com/systemd/systemd/pull/37417
    mesonFlags = mesonFlags ++ [ "-Defi-stub-extra-sections=3000" ];
  });
in

runCommand "spectrum-verity" {
  nativeBuildInputs = [ cryptsetup systemd bash ];
  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
  dontFixup = true;
  passthru = { inherit systemd; };
  env = {
    VERSION = version;
    ROOTHASH = "${verity}/rootfs.verity.roothash";
    VERITY = "${verity}/rootfs.verity.superblock";
    ROOT_FS = rootfs;
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
