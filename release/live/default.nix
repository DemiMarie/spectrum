# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2023, 2025 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

import ../../lib/call-package.nix (
{ callSpectrumPackage, spectrum-build-tools, src
, lib, pkgsStatic, stdenvNoCC
, cryptsetup, dosfstools, jq, mtools, util-linux
, config
}:

let
  inherit (lib) toUpper;

  stdenv = stdenvNoCC;

  efiArch = stdenv.hostPlatform.efiArch;

  efi = callSpectrumPackage ../../host/efi.nix {};
in

stdenv.mkDerivation {
  name = "spectrum-live.img";

  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.intersection src (lib.fileset.unions [
      ./.
      ../../lib/common.mk
      ../../scripts/format-uuid.awk
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
    ROOT_FS = "${efi.rootfs}";
    SYSTEMD_BOOT_EFI = "${efi.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
    SPECTRUM_EFI = efi;
    EFINAME = "BOOT${toUpper efiArch}.EFI";
    VERSION = config.version;
  };

  buildFlags = [ "dest=$(out)" ];

  dontInstall = true;

  enableParallelBuilding = true;

  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
  dontFixup = true;

  passthru = { inherit efi; };
}
) (_: {})
