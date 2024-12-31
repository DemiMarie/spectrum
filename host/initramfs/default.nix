# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

import ../../lib/call-package.nix (
{ src, lseek, rootfs
, lib, stdenvNoCC, makeModulesClosure, runCommand, writeClosure, pkgsStatic
, busybox, cpio, microcodeAmd, microcodeIntel
}:

pkgsStatic.callPackage ({ execline, kmod, mdevd, cryptsetup, util-linuxMinimal }:

let
  inherit (lib) concatMapStringsSep;

  modules = makeModulesClosure {
    inherit (rootfs) firmware kernel;
    rootModules = with rootfs.nixosAllHardware.config.boot.initrd;
      availableKernelModules ++ kernelModules ++ [ "dm-verity" "erofs" "loop" ];
  };

  packages = [
    execline kmod mdevd

    (cryptsetup.override {
      programs = {
        cryptsetup = false;
        cryptsetup-reencrypt = false;
        integritysetup = false;
      };
    })

    (busybox.override {
      enableStatic = true;
      extraConfig = ''
        CONFIG_DEPMOD n
        CONFIG_FINDFS n
        CONFIG_INSMOD n
        CONFIG_LSMOD n
        CONFIG_MODINFO n
        CONFIG_MODPROBE n
        CONFIG_RMMOD n
      '';
    })
  ];

  packagesSysroot = runCommand "packages-sysroot" {} ''
    mkdir -p $out/bin
    ln -s ${concatMapStringsSep " " (p: "${p}/bin/*") packages} $out/bin
    cp -R ${modules}/lib $out
    ln -s /bin $out/sbin

    # TODO: this is a hack and we should just build the util-linux
    # programs we want.
    # https://lore.kernel.org/util-linux/87zgrl6ufb.fsf@alyssa.is/
    cp ${util-linuxMinimal}/bin/{findfs,lsblk} $out/bin
  '';

  microcode = runCommand "microcode.cpio" {
    nativeBuildInputs = [ cpio ];
    __structuredAttrs = true;
    unsafeDiscardReferences = { out = true; };
  } ''
    cpio -id < ${microcodeAmd}/amd-ucode.img
    cpio -id < ${microcodeIntel}/intel-ucode.img
    find kernel | cpio -oH newc -R +0:+0 --reproducible > $out
  '';

  packagesCpio = runCommand "packages.cpio" {
    nativeBuildInputs = [ cpio ];
    storePaths = writeClosure [ packagesSysroot ];
    __structuredAttrs = true;
    unsafeDiscardReferences = { out = true; };
  } ''
    cd ${packagesSysroot}
    (printf "/nix\n/nix/store\n" && find . $(< $storePaths)) |
        cpio -o -H newc -R +0:+0 --reproducible > $out
  '';
in

stdenvNoCC.mkDerivation {
  name = "initramfs";

  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.intersection src (lib.fileset.unions [
      ./.
      ../../lib/common.mk
    ]);
  };
  sourceRoot = "source/host/initramfs";

  env = {
    PACKAGES_CPIO = packagesCpio;
  } // lib.optionalAttrs stdenvNoCC.hostPlatform.isx86_64 {
    MICROCODE = microcode;
  };

  nativeBuildInputs = [ cpio lseek ];

  makeFlags = [ "dest=$(out)" ];

  dontInstall = true;

  enableParallelBuilding = true;

  __structuredAttrs = true;

  unsafeDiscardReferences = { out = true; };

  passthru = { inherit packagesSysroot; };
}
) {}) (_: {})
