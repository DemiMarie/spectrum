# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2023, 2025 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie

import ../../lib/call-package.nix (
{ callSpectrumPackage, spectrum-build-tools, rootfs, src
, lib, pkgsStatic, stdenvNoCC
, cryptsetup, dosfstools, jq, mtools, util-linux
, systemdUkify
}:

let
  inherit (lib) toUpper;

  stdenv = stdenvNoCC;

  systemd = systemdUkify.overrideAttrs ({ mesonFlags ? [], ... }: {
    # The default limit is too low to build a generic aarch64 distro image:
    # https://github.com/systemd/systemd/pull/37417
    mesonFlags = mesonFlags ++ [ "-Defi-stub-extra-sections=3000" ];
  });

  initramfs = callSpectrumPackage ../../host/initramfs {};
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
    cryptsetup dosfstools jq spectrum-build-tools mtools systemd util-linux
  ];

  env = {
    INITRAMFS = initramfs;
    KERNEL = "${rootfs.kernel}/${stdenv.hostPlatform.linux-kernel.target}";
    ROOT_FS = "${rootfs}/rootfs";
    ROOT_FS_VERITY = "${rootfs}/rootfs.verity.superblock";
    ROOT_FS_VERITY_ROOTHASH = "${rootfs}/rootfs.verity.roothash";
    SYSTEMD_BOOT_EFI = "${systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
    EFINAME = "BOOT${toUpper efiArch}.EFI";
  } // lib.optionalAttrs stdenv.hostPlatform.linux-kernel.DTB or false {
    DTBS = "${rootfs.kernel}/dtbs";
  };

  buildFlags = [ "dest=$(out)" ];

  dontInstall = true;

  enableParallelBuilding = true;

  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
  dontFixup = true;

  passthru = { inherit initramfs rootfs; };
}
) (_: {})
