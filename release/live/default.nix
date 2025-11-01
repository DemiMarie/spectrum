# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2023, 2025 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie

import ../../lib/call-package.nix (
{ callSpectrumPackage, spectrum-build-tools, rootfs, src
, lib, pkgsStatic, stdenvNoCC
, cryptsetup, dosfstools, jq, mtools, util-linux
, systemdUkify, efi
}:

let
  inherit (lib) toUpper;

  stdenv = stdenvNoCC;

  efiArch = stdenv.hostPlatform.efiArch;
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
    KERNEL = "${rootfs.kernel}/${stdenv.hostPlatform.linux-kernel.target}";
    ROOT_FS = "${rootfs}/rootfs";
    ROOT_FS_VERITY = "${rootfs}/rootfs.verity.superblock";
    ROOT_FS_VERITY_ROOTHASH = "${rootfs}/rootfs.verity.roothash";
    SYSTEMD_BOOT_EFI = "${efi.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
    EFI_IMAGE = efi;
    EFINAME = "BOOT${toUpper efiArch}.EFI";
  };

  buildFlags = [ "dest=$(out)" ];

  dontInstall = true;

  enableParallelBuilding = true;

  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
  dontFixup = true;

  passthru = { inherit rootfs; };
}
) (_: {})
