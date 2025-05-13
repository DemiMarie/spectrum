# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2023, 2025 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie

import ../../lib/call-package.nix (
{ callSpectrumPackage, lseek, rootfs, src, lib, pkgsStatic, stdenvNoCC
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

  extfs = pkgsStatic.callPackage ../../host/initramfs/extfs.nix {
    inherit callSpectrumPackage;
  };
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
    cryptsetup dosfstools jq lseek mtools systemd util-linux
  ];

  env = {
    EXT_FS = extfs;
    INITRAMFS = initramfs;
    KERNEL = "${rootfs.kernel}/${stdenv.hostPlatform.linux-kernel.target}";
    ROOT_FS = rootfs;
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

  passthru = { inherit initramfs rootfs; };
}
) (_: {})
