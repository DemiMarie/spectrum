# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2023, 2025 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

import ../../lib/call-package.nix (
{ callSpectrumPackage, spectrum-build-tools, rootfs, src
, lib, pkgsStatic, stdenvNoCC
, cryptsetup, dosfstools, jq, mtools, util-linux
, verity, efi
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
      ../../lib/kcmdline-utils.mk
      ../../scripts/format-uuid.awk
      ../../scripts/format-uuid.sh
      ../../scripts/make-gpt.bash
      ../../scripts/make-gpt.sh
      ../../scripts/make-live-image.sh
      ../../scripts/sfdisk-field.awk
      ../../version
    ]);
  };
  sourceRoot = "source/release/live";

  nativeBuildInputs = [
    cryptsetup dosfstools jq spectrum-build-tools mtools util-linux
  ];

  env = {
    ROOT_FS = rootfs;
    ROOT_FS_VERITY = "${verity}/rootfs.verity.superblock";
    ROOT_FS_VERITY_ROOTHASH = "${verity}/rootfs.verity.roothash";
    SYSTEMD_BOOT_EFI = "${efi.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
    EFI_IMAGE = efi;
    EFINAME = "BOOT${toUpper efiArch}.EFI";
    VERSION = import ../../lib/version.nix;
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
