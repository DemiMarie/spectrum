# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2025 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie

import ../../lib/call-package.nix (
{ callSpectrumPackage, lseek, src, pkgsMusl, pkgsStatic, pkgs, linux_latest }:
pkgsStatic.callPackage (

{ spectrum-host-tools
, lib, stdenvNoCC, nixos, runCommand, writeClosure, erofs-utils, s6-rc
, bcachefs-tools, busybox, cloud-hypervisor, cryptsetup, execline
, inkscape, iproute2, inotify-tools, jq, kmod, s6, s6-linux-init, socat
, util-linuxMinimal, virtiofsd, xorg, xdg-desktop-portal-spectrum-host
}:

let
  inherit (nixosAllHardware.config.hardware) firmware;
  inherit (lib)
    concatMapStringsSep concatStrings escapeShellArgs fileset optionalAttrs
    mapAttrsToList systems trivial escapeShellArg;
  inherit (pkgs) dbus dbus-broker glibcLocales systemd;

  pkgsGui = pkgs.extend (
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

  foot = pkgs.foot;

  packages = [
    bcachefs-tools cloud-hypervisor execline inotify-tools
    iproute2 jq kmod s6 s6-linux-init s6-rc socat
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
        CONFIG_CHATTR n
        CONFIG_DEPMOD n
        CONFIG_FINDFS n
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
        CONFIG_RMMOD n
        CONFIG_HALT n
        CONFIG_SHUTDOWN n
        CONFIG_POWEROFF n
      '';
    })
  ] ++ (with pkgs; [ cosmic-files crosvm foot ]);

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
    appvm kernel firmware netvm dbus systemd dbus-broker
  ] ++ (with pkgs; [ mesa dejavu_fonts westonLite ]);

  appvms = {
    appvm-firefox = callSpectrumPackage ../../vm/app/firefox.nix {};
    appvm-foot = callSpectrumPackage ../../vm/app/foot.nix {};
    appvm-gnome-text-editor = callSpectrumPackage ../../vm/app/gnome-text-editor.nix {};
  };

  packagesSysroot = runCommand "packages-sysroot" {
    depsBuildBuild = [ inkscape ];
    nativeBuildInputs = [ xorg.lndir systemd ];
  } ''
    set -eu
    mkdir -p "$out/usr/bin" "$out/etc/dbus-1/services" \
      "$out/usr/share/icons/hicolor/20x20/apps" \
      "$out/etc/systemd/system.conf.d" "$out/usr/lib"
    ln -s -- usr/lib "$out/lib"
    ln -s -- usr/bin "$out/sbin"
    ln -s -- usr/bin "$out/bin"
    ln -s -- bin "$out/usr/sbin"
    # NixOS patches systemd to not support units under /usr/lib or /lib.
    # Work around this.
    ln -s -- ../../etc/systemd "$out/usr/lib/systemd"
    # Same with D-Bus
    ln -s -- ../../etc/dbus-1 "$out/usr/share/dbus-1"
    # Dump anything in etc to /etc not /usr/etc
    ln -s -- ../etc "$out/usr/etc"
    # systemd puts stuff in a weird place
    ln -s -- ../etc "$out/usr/example"

    # Weston doesn't support SVG icons.
    inkscape -w 20 -h 20 \
        -o $out/usr/share/icons/hicolor/20x20/apps/com.system76.CosmicFiles.png \
        ${escapeShellArg pkgs.cosmic-files}/share/icons/hicolor/24x24/apps/com.system76.CosmicFiles.svg

    ln -st "$out/usr/bin" -- \
        ${concatMapStringsSep " " (p: "${escapeShellArg p}/bin/*") packages} \
        ${escapeShellArg pkgs.xdg-desktop-portal}/libexec/xdg-document-portal \
        ${escapeShellArg pkgs.xdg-desktop-portal-gtk}/libexec/xdg-desktop-portal-gtk
    ln -st "$out/usr/share/dbus-1" -- \
        ${escapeShellArg dbus}/share/dbus-1/session.conf
    ln -st "$out/usr/share/dbus-1/services" -- \
        ${escapeShellArg pkgs.xdg-desktop-portal-gtk}/share/dbus-1/services/org.freedesktop.impl.portal.desktop.gtk.service

    for pkg in ${escapeShellArgs usrPackages}; do
        # Populate /usr.
        lndir -ignorelinks -silent "$pkg" "$out/usr/"
        # lndir does not follow symlinks in the target directory unless
        # the symlink is on the command line and followed by /, so for
        # each symlink there it is necessary to run lndir again.
        for subdir in example share/dbus-1 lib/systemd etc; do
            if [ -d "$pkg/$subdir" ]; then
                lndir -silent -ignorelinks "$pkg/$subdir" "$out/usr/$subdir"
            fi
        done
    done

    # Clean up some unneeded stuff
    rm -- "$out/usr/etc" "$out/usr/lib/systemd" "$out/usr/share/dbus-1" "$out/usr/example" "$out"/usr/lib/*.so*

    # Tell glibc where the locale archive is
    locale_archive=${escapeShellArg glibcLocales}
    case $locale_archive in
    (*[!0-9A-Za-z._/-]*) echo "Bad locale archive path?" >&2; exit 1;;
    (/*) :;;
    (*) echo "Locale archive not absolute?" >&2; exit 1;;
    esac
    printf '[Manager]
DefaultEnvironment=LOCALE_ARCHIVE=%s
' "$locale_archive" > "$out/etc/systemd/system.conf.d/zspectrum-locale.conf"

    # Fix the D-Bus config files so they don't include themselves
    for scope in system session; do
        sed -i -- "/\/etc\/dbus-1\/$scope\.conf/d" "$out/etc/dbus-1/$scope.conf"
    done

    # switch_root (used by initramfs) expects init to be at /etc/init,
    # but that just mounts /etc as a writable overlayfs and then executes
    # /sbin/init.
    ln -sf -- ../../${escapeShellArg systemd}/lib/systemd/systemd "$out/usr/bin/init"

    ${concatStrings (mapAttrsToList (name: path: ''
      ln -s -- ${escapeShellArg path} "$out"/usr/lib/spectrum/vm/${escapeShellArg name}
    '') appvms)}

    # TODO: this is a hack and we should just build the util-linux
    # programs we want.
    # https://lore.kernel.org/util-linux/87zgrl6ufb.fsf@alyssa.is/
    ln -s ${util-linuxMinimal}/bin/{findfs,uuidgen,lsblk,mount} $out/usr/bin

    # Set up users and groups
    systemd-sysusers --root "$out"
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

  nativeBuildInputs = [ erofs-utils lseek s6-rc systemd ];

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
    inherit appvm firmware kernel nixosAllHardware packagesSysroot;
  };

  meta = with lib; {
    license = licenses.eupl12;
    platforms = platforms.linux;
  };
}
) {}) (_: {})
