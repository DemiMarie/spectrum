# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie

import ../../lib/call-package.nix (
{ callSpectrumPackage, lseek, src, pkgsMusl, pkgsStatic, linux_latest }:
pkgsStatic.callPackage (

{ start-vmm
, lib, stdenvNoCC, nixos, runCommand, writeClosure, erofs-utils, s6-rc, busybox
, cloud-hypervisor, cryptsetup, dbus, execline, e2fsprogs, inkscape, jq, kmod
, mdevd, s6, s6-linux-init, socat, util-linuxMinimal, virtiofsd, xorg
, xdg-desktop-portal-spectrum-host
}:

let
  inherit (lib) concatMapStringsSep optionalAttrs systems;
  inherit (nixosAllHardware.config.hardware) firmware;

  pkgsGui = pkgsMusl.extend (
    final: super:
    (optionalAttrs (systems.equals pkgsMusl.stdenv.hostPlatform super.stdenv.hostPlatform) {
      appstream = super.appstream.override {
        withSystemd = false;
      };
      at-spi2-core = super.at-spi2-core.override {
        systemdSupport = false;
      };
      colord = super.colord.override {
        enableSystemd = false;
      };
      flatpak = super.flatpak.override {
        withMalcontent = false;
        withSystemd = false;
      };
      gcr_4 = super.gcr_4.override {
        systemdSupport = false;
      };
      gnome-desktop = super.gnome-desktop.override {
        withSystemd = false;
      };
      gnome-settings-daemon = super.gnome-settings-daemon.override {
        withSystemd = false;
      };

      libgudev = super.libgudev.overrideAttrs ({ ... }: {
        # Tests use umockdev, which is not compatible with libudev-zero.
        doCheck = false;
      });

      modemmanager = super.modemmanager.override {
        withSystemd = false;
      };
      networkmanager = super.networkmanager.override {
        withSystemd = false;
      };
      pcsclite = super.pcsclite.override {
        systemdSupport = false;
      };
      pipewire = super.pipewire.override {
        enableSystemd = false;
      };
      polkit = super.polkit.override {
        useSystemd = false;
      };
      postgresql = super.postgresql.override {
        systemdSupport = false;
      };
      ppp = super.ppp.override {
        withSystemd = false;
      };
      procps = super.procps.override {
        withSystemd = false;
      };
      pulseaudio = super.pulseaudio.override {
        useSystemd = false;
      };

      systemd = final.libudev-zero;
      systemdLibs = final.libudev-zero;
      systemdMinimal = final.libudev-zero;

      seatd = super.seatd.override {
        systemdSupport = false;
      };

      tinysparql = super.tinysparql.overrideAttrs ({ mesonFlags ? [], ... }: {
        mesonFlags = mesonFlags ++ [ "-Dsystemd_user_services=false" ];
      });

      upower = super.upower.override {
        withSystemd = false;

        # Not ideal, but it's the best way to get rid of an installed
        # test that needs umockdev.
        withIntrospection = false;
      };

      util-linux = super.util-linux.override {
        systemdSupport = false;
      };

      weston = super.weston.overrideAttrs ({ mesonFlags ? [], ... }: {
        mesonFlags = mesonFlags ++ [
          "-Dsystemd=false"
        ];
      });

      xdg-desktop-portal = super.xdg-desktop-portal.override {
        enableSystemd = false;
      };
    })
  );

  foot = pkgsGui.foot.override { allowPgo = false; };

  packages = [
    cloud-hypervisor dbus e2fsprogs execline jq kmod mdevd
    s6 s6-linux-init s6-rc socat start-vmm virtiofsd
    xdg-desktop-portal-spectrum-host

    (cryptsetup.override {
      programs = {
        cryptsetup = false;
        cryptsetup-reencrypt = false;
        integritysetup = false;
      };
    })

    (busybox.override {
      extraConfig = ''
        CONFIG_CHATTR n
        CONFIG_DEPMOD n
        CONFIG_FINDFS n
        CONFIG_INIT n
        CONFIG_INSMOD n
        CONFIG_LSATTR n
        CONFIG_LSMOD n
        CONFIG_MKE2FS n
        CONFIG_MKFS_EXT2 n
        CONFIG_MODINFO n
        CONFIG_MODPROBE n
        CONFIG_MOUNT n
        CONFIG_RMMOD n
      '';
    })
  ] ++ (with pkgsGui; [ cosmic-files crosvm foot ]);

  nixosAllHardware = nixos ({ modulesPath, ... }: {
    imports = [ (modulesPath + "/profiles/all-hardware.nix") ];

    system.stateVersion = lib.trivial.release;
  });

  kernel = linux_latest;

  appvm = callSpectrumPackage ../../img/app { inherit (foot) terminfo; };

  # Packages that should be fully linked into /usr,
  # (not just their bin/* files).
  usrPackages = [
    appvm kernel firmware
  ] ++ (with pkgsGui; [ mesa.drivers dejavu_fonts westonLite ]);

  packagesSysroot = runCommand "packages-sysroot" {
    depsBuildBuild = [ inkscape ];
    nativeBuildInputs = [ xorg.lndir ];
  } ''
    mkdir -p $out/usr/bin $out/usr/share/dbus-1/services \
      $out/usr/share/icons/hicolor/20x20/apps

    # Weston doesn't support SVG icons.
    inkscape -w 20 -h 20 \
        -o $out/usr/share/icons/hicolor/20x20/apps/com.system76.CosmicFiles.png \
        ${pkgsGui.cosmic-files}/share/icons/hicolor/24x24/apps/com.system76.CosmicFiles.svg

    ln -st $out/usr/bin \
        ${concatMapStringsSep " " (p: "${p}/bin/*") packages} \
        ${pkgsGui.xdg-desktop-portal}/libexec/xdg-document-portal \
        ${pkgsGui.xdg-desktop-portal-gtk}/libexec/xdg-desktop-portal-gtk
    ln -st $out/usr/share/dbus-1 \
        ${dbus}/share/dbus-1/session.conf
    ln -st $out/usr/share/dbus-1/services \
        ${pkgsGui.xdg-desktop-portal-gtk}/share/dbus-1/services/org.freedesktop.impl.portal.desktop.gtk.service

    for pkg in ${lib.escapeShellArgs usrPackages}; do
        lndir -ignorelinks -silent "$pkg" "$out/usr"
    done

    # TODO: this is a hack and we should just build the util-linux
    # programs we want.
    # https://lore.kernel.org/util-linux/87zgrl6ufb.fsf@alyssa.is/
    ln -s ${util-linuxMinimal}/bin/{findfs,uuidgen,lsblk,mount} $out/usr/bin
  '';
in

stdenvNoCC.mkDerivation {
  name = "spectrum-rootfs";

  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.intersection src (lib.fileset.unions [
      ./.
      ../../lib/common.mk
      ../../scripts/make-erofs.sh
    ]);
  };
  sourceRoot = "source/host/rootfs";

  nativeBuildInputs = [ erofs-utils lseek s6-rc ];

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

  passthru = {
    inherit appvm firmware kernel nixosAllHardware packagesSysroot pkgsGui;
  };

  meta = with lib; {
    license = licenses.eupl12;
    platforms = platforms.linux;
  };
}
) {}) (_: {})
