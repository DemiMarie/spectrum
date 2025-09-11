# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2025 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie

import ../../lib/call-package.nix (
{ callSpectrumPackage, spectrum-build-tools, src
, pkgsMusl, pkgsStatic, linux_latest
}:
pkgsStatic.callPackage (

{ busybox, cloud-hypervisor, cryptsetup, dbus, erofs-utils, execline
, inkscape, inotify-tools, iproute2, jq, lib, mdevd, nixos
, runCommand, s6, s6-linux-init, s6-rc, socat, spectrum-host-tools
, stdenvNoCC, util-linuxMinimal, virtiofsd, writeClosure
, xdg-desktop-portal-spectrum-host, xorg
}:
let
  inherit (lib)
    concatMapStringsSep concatStrings escapeShellArgs fileset
    mapAttrsToList systems trivial;
  pkgsGui = pkgsMusl.extend (
    _final: super:
    (lib.optionalAttrs (systems.equals pkgsMusl.stdenv.hostPlatform super.stdenv.hostPlatform) {
      malcontent = super.malcontent.overrideAttrs ({ meta ? { }, ... }: {
        meta = meta // {
          platforms = [ ];
        };
      });
   }));
in
# Something already pulls in the full
# systemd, so might as well use it.
pkgsGui.callPackage (
{ cosmic-files, crosvm, dejavu_fonts, foot, kmod, mesa
, systemd, westonLite, xdg-desktop-portal, xdg-desktop-portal-gtk
}:

let
  inherit (nixosAllHardware.config.hardware) firmware;
  no_pgo_foot = foot.override { allowPgo = false; };

  packages = [
    cloud-hypervisor crosvm cryptsetup dbus execline inotify-tools
    iproute2 jq mdevd s6 s6-linux-init s6-rc socat
    spectrum-host-tools virtiofsd xdg-desktop-portal-spectrum-host

    (busybox.override {
      extraConfig = ''
        CONFIG_CHATTR n
        CONFIG_DEPMOD n
        CONFIG_FINDFS n
        CONFIG_HALT n
        CONFIG_INIT n
        CONFIG_INSMOD n
        CONFIG_IP n
        CONFIG_LSATTR n
        CONFIG_LSMOD n
        CONFIG_MKE2FS n
        CONFIG_MKFS_EXT2 n
        CONFIG_MODINFO n
        CONFIG_MODPROBE n
        CONFIG_MOUNT n
        CONFIG_POWEROFF n
        CONFIG_REBOOT n
        CONFIG_RMMOD n
        CONFIG_SHUTDOWN n
      '';
    })
  ];

  nixosAllHardware = nixos ({ modulesPath, ... }: {
    imports = [ (modulesPath + "/profiles/all-hardware.nix") ];

    system.stateVersion = trivial.release;
  });

  kernel = linux_latest;

  appvm = callSpectrumPackage ../../img/app { inherit (no_pgo_foot) terminfo; };
  netvm = callSpectrumPackage ../../vm/sys/net { inherit (no_pgo_foot) terminfo; };

  # Packages that should be fully linked into /usr,
  # (not just their bin/* files).
  usrPackages = [
    appvm kernel.modules firmware kmod kmod.lib
    netvm mesa dejavu_fonts westonLite
  ];

  appvms = {
    appvm-firefox = callSpectrumPackage ../../vm/app/firefox.nix {};
    appvm-foot = callSpectrumPackage ../../vm/app/foot.nix {};
    appvm-gnome-text-editor = callSpectrumPackage ../../vm/app/gnome-text-editor.nix {};
  };

  packagesSysroot = runCommand "packages-sysroot" {
    depsBuildBuild = [ inkscape ];
    nativeBuildInputs = [ xorg.lndir ];
  } ''
    mkdir -p $out/usr/bin $out/usr/share/dbus-1/services \
      $out/usr/share/icons/hicolor/20x20/apps

    # Weston doesn't support SVG icons.
    inkscape -w 20 -h 20 \
        -o $out/usr/share/icons/hicolor/20x20/apps/com.system76.CosmicFiles.png \
        ${cosmic-files}/share/icons/hicolor/24x24/apps/com.system76.CosmicFiles.svg

    ln -st $out/usr/bin \
        ${concatMapStringsSep " " (p: "${p}/bin/*") packages} \
        ${xdg-desktop-portal}/libexec/xdg-document-portal \
        ${xdg-desktop-portal-gtk}/libexec/xdg-desktop-portal-gtk
    ln -st $out/usr/share/dbus-1 \
        ${dbus}/share/dbus-1/session.conf
    ln -st $out/usr/share/dbus-1/services \
        ${xdg-desktop-portal-gtk}/share/dbus-1/services/org.freedesktop.impl.portal.desktop.gtk.service

    for pkg in ${escapeShellArgs usrPackages}; do
        lndir -ignorelinks -silent "$pkg" "$out/usr"
    done

    ${concatStrings (mapAttrsToList (name: path: ''
      ln -s ${path} $out/usr/lib/spectrum/vm/${name}
    '') appvms)}

    # TODO: this is a hack and we should just build the util-linux
    # programs we want.
    # https://lore.kernel.org/util-linux/87zgrl6ufb.fsf@alyssa.is/
    ln -s ${util-linuxMinimal}/bin/{findfs,uuidgen,lsblk,mount} $out/usr/bin

    # TODO: this is another hack and it should be possible
    # to build systemd without this.
    ln -s -- ${lib.escapeShellArg systemd}/bin/udevadm "$out/usr/bin"
  '';
in

stdenvNoCC.mkDerivation {
  name = "spectrum-rootfs";

  src = fileset.toSource {
    root = ../..;
    fileset = fileset.intersection src (fileset.unions [
      ./.
      ../../lib/common.mk
      ../../scripts/make-erofs.sh
    ]);
  };
  sourceRoot = "source/host/rootfs";

  nativeBuildInputs = [ erofs-utils spectrum-build-tools s6-rc ];

  env = {
    PACKAGES = runCommand "packages" {} ''
      printf "%s\n/\n" ${packagesSysroot} >$out
      sed p ${writeClosure [ packagesSysroot] } >>$out
    '';
  };

  makeFlags = [ "dest=$(out)" ];

  dontInstall = true;

  enableParallelBuilding = true;

  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
  dontFixup = true;

  passthru = {
    inherit appvm firmware kernel nixosAllHardware packagesSysroot;
  };

  meta = with lib; {
    license = licenses.eupl12;
    platforms = platforms.linux;
  };
}
) {}) {}) (_: {})
