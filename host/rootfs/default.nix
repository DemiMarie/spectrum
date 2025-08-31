# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2025 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie

import ../../lib/call-package.nix (
{ callSpectrumPackage, lseek, src, pkgsMusl, pkgsStatic, linux_latest }:
pkgsStatic.callPackage (

{ spectrum-host-tools
, lib, stdenvNoCC, nixos, runCommand, writeClosure, erofs-utils, s6-rc
, bcachefs-tools, busybox, cloud-hypervisor, cryptsetup, dbus, execline
, inkscape, iproute2, inotify-tools, jq, kmod, less, mdevd, s6, s6-linux-init
, socat, util-linuxMinimal, virtiofsd, xorg, xdg-desktop-portal-spectrum-host
}:

let
  inherit (nixosAllHardware.config.hardware) firmware;
  inherit (lib)
    concatMapStringsSep concatStrings escapeShellArgs fileset optionalAttrs
    mapAttrsToList systems trivial;

  pkgsGui = pkgsMusl.extend (
    final: super:
    (optionalAttrs (systems.equals pkgsMusl.stdenv.hostPlatform super.stdenv.hostPlatform) {
      flatpak = super.flatpak.override {
        withMalcontent = false;
      };

      libgudev = super.libgudev.overrideAttrs ({ ... }: {
        # Tests use umockdev, which is not compatible with libudev-zero.
        doCheck = false;
      });

      qt6 = super.qt6.overrideScope (_: prev: {
        qttranslations = prev.qttranslations.override {
          qttools = prev.qttools.override {
            qtbase = prev.qtbase.override {
              qttranslations = null;
              systemdSupport = false;
            };
            qtdeclarative = null;
          };
        };

        qtbase = prev.qtbase.override {
          systemdSupport = false;
        };
      });

      systemd = super.systemd.overrideAttrs ({ meta ? { }, ... }: {
        meta = meta // {
          platforms = [ ];
        };
      });

      upower = super.upower.override {
        # Not ideal, but it's the best way to get rid of an installed
        # test that needs umockdev.
        withIntrospection = false;
      };

      udev = final.libudev-zero;

      weston = super.weston.overrideAttrs ({ mesonFlags ? [], ... }: {
        mesonFlags = mesonFlags ++ [
          "-Dsystemd=false"
        ];
      });

      xdg-desktop-portal = (super.xdg-desktop-portal.override {
        enableSystemd = false;
      }).overrideAttrs ({ ... }: {
        # Tests use umockdev.
        doCheck = false;
      });
    })
  );

  foot = pkgsGui.foot.override { allowPgo = false; };

  packages = [
    bcachefs-tools cloud-hypervisor dbus execline inotify-tools
    iproute2 jq kmod less mdevd s6 s6-linux-init s6-rc socat
    spectrum-host-tools virtiofsd xdg-desktop-portal-spectrum-host

    (cryptsetup.override {
      programs = {
        cryptsetup = false;
        cryptsetup-reencrypt = false;
        integritysetup = false;
      };
    })

    (busybox.override {
      extraConfig = ''
        CONFIG_ACPID n
        CONFIG_ARP n
        CONFIG_ARPING n
        CONFIG_BEEP n
        CONFIG_BOOTCHARTD n
        CONFIG_BRCTL n
        CONFIG_CAL n
        CONFIG_CHAT n
        CONFIG_CHATTR n
        CONFIG_CHPST n
        CONFIG_CROND n
        CONFIG_CRONTAB n
        CONFIG_DEPMOD n
        CONFIG_DEVMEM n
        CONFIG_DHCPRELAY n
        CONFIG_DNSD n
        CONFIG_DUMPLEASES n
        CONFIG_DUMPRELAY n
        CONFIG_FAKEIDENTD n
        CONFIG_FEATURE_HWIB n
        CONFIG_FEATURE_IP_ADDRESS n
        CONFIG_FEATURE_IP_LINK n
        CONFIG_FEATURE_IP_NEIGH n
        CONFIG_FEATURE_IP_ROUTE n
        CONFIG_FEATURE_IP_RULE n
        CONFIG_FEATURE_IP_TUNNEL n
        CONFIG_FEATURE_UNIX_LOCAL n
        CONFIG_FINDFS n
        CONFIG_FLASHCP n
        CONFIG_FLASH_ERASEALL n
        CONFIG_FLASH_LOCK n
        CONFIG_FLASH_UNLOCK n
        CONFIG_FSCK n
        CONFIG_FSCK_MINIX n
        CONFIG_FTPD n
        CONFIG_FTPGET n
        CONFIG_FTPPUT n
        CONFIG_HTTPD n
        CONFIG_HUSH n
        CONFIG_I2CDETECT n
        CONFIG_I2CDUMP n
        CONFIG_I2CGET n
        CONFIG_I2CSET n
        CONFIG_I2CTRANSFER n
        CONFIG_IFCONFIG n
        CONFIG_IFDOWN n
        CONFIG_IFENSLAVE n
        CONFIG_IFPLUGD n
        CONFIG_IFUP n
        CONFIG_INETD n
        CONFIG_INIT n
        CONFIG_INOTIFYD n
        CONFIG_INSMOD n
        CONFIG_IP n
        CONFIG_IPADDR n
        CONFIG_IPLINK n
        CONFIG_IPROUTE n
        CONFIG_IPRULE n
        CONFIG_IPTUNNEL n
        CONFIG_LESS n
        CONFIG_LINUXRC n
        CONFIG_LPD n
        CONFIG_LPQ n
        CONFIG_LPR n
        CONFIG_LSATTR n
        CONFIG_LSMOD n
        CONFIG_MAKEDEVS n
        CONFIG_MAKEMIME n
        CONFIG_MDEV n
        CONFIG_MESG n
        CONFIG_MIM n
        CONFIG_MKDOSFS n
        CONFIG_MKE2FS n
        CONFIG_MKFS_EXT2 n
        CONFIG_MKFS_REISER n
        CONFIG_MODINFO n
        CONFIG_MODPROBE n
        CONFIG_MODPROBE_SMALL n
        CONFIG_MOUNT n
        CONFIG_MT n
        CONFIG_NAMDWRITE n
        CONFIG_NAMEIF n
        CONFIG_NANDDUMP n
        CONFIG_NBDCLIENT n
        CONFIG_NETSTAT n
        CONFIG_NSLOOKUP n
        CONFIG_NTPD n
        CONFIG_PING n
        CONFIG_PING6 n
        CONFIG_POPMAILDIR n
        CONFIG_PSCAN n
        CONFIG_REFORMMIME n
        CONFIG_RMMOD n
        CONFIG_ROUTE n
        CONFIG_RUNSV n
        CONFIG_RUNSVDIR n
        CONFIG_SENDMAIL n
        CONFIG_SETARCH n
        CONFIG_SLATTACH n
        CONFIG_SSL_CLIENT n
        CONFIG_START_STOP_DAEMON n
        CONFIG_SV n
        CONFIG_SVC n
        CONFIG_SVLOGD n
        CONFIG_SVOK n
        CONFIG_TC n
        CONFIG_TCPSVD n
        CONFIG_TELNET n
        CONFIG_TELNETD n
        CONFIG_TFTP n
        CONFIG_TFTPD n
        CONFIG_TRACEROUTE n
        CONFIG_TRACEROUTE6 n
        CONFIG_TUNCTL n
        CONFIG_UBIATTACH n
        CONFIG_UBIDETACH n
        CONFIG_UBIMKVOL n
        CONFIG_UBIRENAME n
        CONFIG_UBIRMVOL n
        CONFIG_UBIRSVOL n
        CONFIG_UBIUPDATEVOL n
        CONFIG_UDHCP6 n
        CONFIG_UDHCPC n
        CONFIG_UDHCPC6 n
        CONFIG_UDHCPD n
        CONFIG_UDPSVD n
        CONFIG_UPDATEVOL n
        CONFIG_VCONFIG n
        CONFIG_WALL n
        CONFIG_WGET n
        CONFIG_WHOIS n
        CONFIG_ZCIP n
      '';
    })
  ] ++ (with pkgsGui; [ cosmic-files crosvm foot ]);

  nixosAllHardware = nixos ({ modulesPath, ... }: {
    imports = [ (modulesPath + "/profiles/all-hardware.nix") ];

    system.stateVersion = trivial.release;
  });

  kernel = linux_latest;

  appvm = callSpectrumPackage ../../img/app { inherit (foot) terminfo; };
  netvm = callSpectrumPackage ../../vm/sys/net { inherit (foot) terminfo; };

  # Packages that should be fully linked into /usr,
  # (not just their bin/* files).
  usrPackages = [
    appvm kernel firmware netvm
  ] ++ (with pkgsGui; [ mesa dejavu_fonts westonLite ]);

  appvms = {
    appvm-firefox = callSpectrumPackage ../../vm/app/firefox.nix {};
    appvm-foot = callSpectrumPackage ../../vm/app/foot.nix {};
    appvm-gnome-text-editor = callSpectrumPackage ../../vm/app/gnome-text-editor.nix {};
  };

  packagesSysroot = runCommand "packages-sysroot" {
    depsBuildBuild = [ inkscape ];
    nativeBuildInputs = [ xorg.lndir ];
  } ''
    set -eu
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
