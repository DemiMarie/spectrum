# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix (
{ lseek, src, terminfo, pkgsStatic, buildFHSEnv, appimageTools }:

pkgsStatic.callPackage (
{ lib, stdenvNoCC, runCommand, writeClosure
, erofs-utils, jq, s6-rc, util-linux
, busybox, cacert, dejavu_fonts, execline, kmod, linux_latest, mdevd, s6
, s6-linux-init, spectrum-guest-tools
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

      (busybox.override {
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

      cacert
      dejavu_fonts
      execline
      kmod
      mdevd
      s6
      s6-linux-init
      s6-rc
      spectrum-guest-tools
      terminfo

      # Some packages can't (currently?) be built statically.

      # https://github.com/nix-ocaml/nix-overlays/issues/698
      pkgs.wayland-proxy-virtwl
      # Depends on xcvt, which can't be built statically.
      pkgs.xwayland
      pkgs.xdg-desktop-portal
      pkgs.xdg-desktop-portal-gtk
      # Depends on pulseaudio libs
      pkgs.pipewire
      pkgs.wireplumber
    ];
  })).fhsenv;

  packagesSysroot = runCommand "packages-sysroot" {} ''
    set -eu
    mkdir -p -- "$out/etc/ssl/certs" "$out/usr/bin"
    # ../../scripts/make-erofs.sh will re-create these
    rm -f -- "$out/usr/lib64" "$out/usr/lib"
    source_dir=${lib.escapeShellArg appimageFhsenv}/usr
    for i in "$source_dir"/*; do
      subdir=''${i##*/}
      case $subdir in
      (bin|include|lib|lib64|libexec|sbin|share) :;;
      (*) printf 'Bad subdirectory %s\n' "$subdir" >&2; exit 1;;
      esac
    done
    if ! [ -h "$source_dir/lib" ]; then echo "FHSenv didn't make lib a symlink" >&2; exit 1; fi
    ln -s -- "$source_dir/include" "$source_dir/libexec" "$source_dir/share" "$out/usr"
    cp -RT -- "$source_dir/lib64" "$out/usr/lib"
    # Do this first so that the subsequent call to cp (without -T)
    # will create new entries in the existing bin directory.
    cp -RT -- "$source_dir/sbin" "$out/usr/bin"
    # with -T cp tries to delete the whole target directory first
    cp -R -- "$source_dir/bin" "$out/usr"
    # so that ln can make the symlink
    chmod -- 0755 "$out/usr/lib"
    ln -s -- ${lib.escapeShellArg kernel}/lib/modules "$out/usr/lib/"
    ln -s -- ${lib.escapeShellArg cacert}/etc/ssl/certs/* "$out/etc/ssl/certs"
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

  nativeBuildInputs = [ erofs-utils jq lseek s6-rc util-linux ];

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

  meta = with lib; {
    license = licenses.eupl12;
    platforms = platforms.linux;
  };
}
) {}) ({ foot }: { inherit (foot) terminfo; })
