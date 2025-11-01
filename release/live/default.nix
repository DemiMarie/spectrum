# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2023, 2025 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie

import ../../lib/call-package.nix (
{ callSpectrumPackage, spectrum-build-tools, src
, lib, pkgsStatic, stdenvNoCC
, cryptsetup, dosfstools, jq, mtools, util-linux
}:

let
  inherit (lib) toUpper;

  stdenv = stdenvNoCC;

  efiArch = stdenv.hostPlatform.efiArch;

  efi = callSpectrumPackage ../../host/efi.nix {};

  # The initramfs and rootfs must match those used to build the UKI.
  inherit (efi) initramfs rootfs systemd;
in

stdenv.mkDerivation {
  name = "spectrum-live.img";

  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.intersection src (lib.fileset.unions [
      ./.
      ../../lib/common.mk
      ../../scripts/format-uuid.sh
      ../../scripts/make-gpt.sh
      ../../scripts/sfdisk-field.awk
    ]);
  };
  sourceRoot = "source/release/live";

  nativeBuildInputs = [
    cryptsetup dosfstools jq spectrum-build-tools mtools util-linux
  ];

  env = {
    KERNEL = "${efi.rootfs.kernel}/${stdenv.hostPlatform.linux-kernel.target}";
    ROOT_FS_DIR = "${efi.rootfs}";
    SYSTEMD_BOOT_EFI = "${systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
    EFI_IMAGE = efi;
    EFINAME = "BOOT${toUpper efiArch}.EFI";
  };

  buildFlags = [ "dest=$(out)" ];

  dontInstall = true;

  enableParallelBuilding = true;

  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
  dontFixup = true;

  passthru = { inherit efi initramfs rootfs; };
}
) (_: {})
