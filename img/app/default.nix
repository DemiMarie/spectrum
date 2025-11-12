# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2025 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix (
{ spectrum-app-tools, spectrum-build-tools, src, terminfo
, lib, appimageTools, buildFHSEnv, runCommand, stdenvNoCC, writeClosure
, erofs-utils, jq, s6-rc, util-linux, xorg
, cacert, linux_latest
}:

let
  kernelTarget =
    if stdenvNoCC.hostPlatform.isx86 then
      # vmlinux.bin is the stripped version of vmlinux.
      # Confusingly, compressed/vmlinux.bin is the stripped version of
      # the top-level vmlinux target, while the top-level vmlinux.bin
      # is the stripped version of compressed/vmlinux.  So we use
      # compressed/vmlinux.bin, since we want a stripped version of
      # the kernel that *hasn't* been built to be compressed.  Weird!
      "compressed/vmlinux.bin"
    else
      stdenvNoCC.hostPlatform.linux-kernel.target;

  kernel = (linux_latest.override {
    structuredExtraConfig = with lib.kernel; {
      DRM_FBDEV_EMULATION = lib.mkForce no;
      EROFS_FS = yes;
      FONTS = lib.mkForce unset;
      FONT_8x8 = lib.mkForce unset;
      FONT_TER16x32 = lib.mkForce unset;
      FRAMEBUFFER_CONSOLE = lib.mkForce unset;
      FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER = lib.mkForce unset;
      FRAMEBUFFER_CONSOLE_DETECT_PRIMARY = lib.mkForce unset;
      FRAMEBUFFER_CONSOLE_ROTATION = lib.mkForce unset;
      RC_CORE = lib.mkForce unset;
      VIRTIO = yes;
      VIRTIO_BLK = yes;
      VIRTIO_CONSOLE = yes;
      VIRTIO_PCI = yes;
      VT = no;
    };
  }).overrideAttrs ({ installFlags ? [], ... }: {
    installFlags = installFlags ++ [
      "KBUILD_IMAGE=$(boot)/${kernelTarget}"
    ];
  });

  appimageFhsenv = (buildFHSEnv (appimageTools.defaultFhsEnvArgs // {
    name = "vm-fhs-env";
    targetPkgs = pkgs: appimageTools.defaultFhsEnvArgs.targetPkgs pkgs ++ [
      pkgs.fuse

      (pkgs.busybox.override {
        enableMinimal = true;
        extraConfig = ''
          CONFIG_CLEAR y
          CONFIG_FEATURE_IP_ADDRESS y
          CONFIG_FEATURE_IP_LINK y
          CONFIG_FEATURE_IP_ROUTE y
          CONFIG_INIT n
          CONFIG_IP y
        '';
      })

      pkgs.cacert
      pkgs.dejavu_fonts
      pkgs.execline
      pkgs.kmod
      pkgs.mdevd
      pkgs.pipewire
      pkgs.s6
      pkgs.s6-linux-init
      pkgs.s6-rc
      pkgs.wayland-proxy-virtwl
      pkgs.wireplumber
      pkgs.xdg-desktop-portal
      pkgs.xdg-desktop-portal-gtk
      pkgs.xwayland

      kernel.modules
      spectrum-app-tools
      terminfo
    ];
  })).fhsenv;

  packagesSysroot = runCommand "packages-sysroot" {
    nativeBuildInputs = [ xorg.lndir ];
  } ''
    mkdir $out
    lndir -ignorelinks -silent ${appimageFhsenv} $out
    rm $out/etc/dbus-1/session.conf $out/etc/fonts/fonts.conf
  '';
in

stdenvNoCC.mkDerivation {
  name = "spectrum-appvm";

  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.intersection src (lib.fileset.unions [
      ./.
      ../../lib/common.mk
      ../../scripts/make-erofs.sh
      ../../scripts/make-gpt.sh
      ../../scripts/sfdisk-field.awk
    ]);
  };
  sourceRoot = "source/img/app";

  nativeBuildInputs = [ erofs-utils jq spectrum-build-tools s6-rc util-linux ];

  env = {
    KERNEL = "${kernel}/${baseNameOf kernelTarget}";
    PACKAGES = runCommand "packages" {} ''
      printf "%s\n/\n" ${packagesSysroot} >$out
      sed p ${writeClosure [ packagesSysroot] } >>$out
    '';
  };

  makeFlags = [ "prefix=$(out)" ];

  dontInstall = true;

  enableParallelBuilding = true;

  passthru = { inherit appimageFhsenv kernel packagesSysroot; };

  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
  dontFixup = true;

  meta = with lib; {
    license = licenses.eupl12;
    platforms = platforms.linux;
  };
}
) ({ foot }: { inherit (foot) terminfo; })
