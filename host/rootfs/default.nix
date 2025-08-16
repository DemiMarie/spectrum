# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2025 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie

import ../../lib/call-package.nix (
{ callSpectrumPackage, lseek, src, pkgsMusl, pkgsStatic, pkgs, linux_latest }:
pkgsStatic.callPackage (

{ spectrum-host-tools
, lib, stdenvNoCC, nixos, runCommand, writeClosure, erofs-utils, s6-rc
, bcachefs-tools, busybox, cloud-hypervisor, cryptsetup, execline, inkscape
, iproute2, inotify-tools, jq, kmod, less, s6, s6-linux-init, socat
, virtiofsd, xorg, xdg-desktop-portal-spectrum-host, shadow
}:
pkgs.callPackage (
{ cosmic-files, crosvm, dbus, dejavu_fonts, foot
, glibcLocales, linux-pam, mesa, systemd, util-linux
, westonLite, xdg-desktop-portal, xdg-desktop-portal-gtk
}:

let
  inherit (nixosAllHardware.config.hardware) firmware;
  inherit (lib)
    concatMapStringsSep concatStrings escapeShellArgs fileset
    mapAttrsToList trivial escapeShellArg;

  spectrum_busybox =
    busybox.override {
      # avoid conflicting with util-linux login
      extraConfig = ''
        CONFIG_CHATTR n
        CONFIG_DEPMOD n
        CONFIG_FINDFS n
        CONFIG_HALT n
        CONFIG_INIT n
        CONFIG_INSMOD n
        CONFIG_IP n
        CONFIG_LESS n
        CONFIG_LSATTR n
        CONFIG_LSMOD n
        CONFIG_MKE2FS n
        CONFIG_MKFS_EXT2 n
        CONFIG_MODINFO n
        CONFIG_MODPROBE n
        CONFIG_MOUNT n
        CONFIG_RMMOD n
        CONFIG_POWEROFF n
        CONFIG_REBOOT n
        CONFIG_SHUTDOWN n
      '';
    };

  packages = [
    bcachefs-tools cloud-hypervisor cosmic-files crosvm execline
    foot inotify-tools iproute2 jq kmod less s6 s6-linux-init s6-rc
    socat spectrum-host-tools virtiofsd xdg-desktop-portal-spectrum-host
    (cryptsetup.override {
      programs = {
        cryptsetup = false;
        cryptsetup-reencrypt = false;
        integritysetup = false;
      };
    })
  ];

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
    appvm dbus dejavu_fonts firmware kernel mesa
    netvm systemd util-linux westonLite
  ];

  appvms = {
    appvm-firefox = callSpectrumPackage ../../vm/app/firefox.nix {};
    appvm-foot = callSpectrumPackage ../../vm/app/foot.nix {};
    appvm-gnome-text-editor = callSpectrumPackage ../../vm/app/gnome-text-editor.nix {};
  };

  packagesSysroot = runCommand "packages-sysroot" {
    depsBuildBuild = [ inkscape ];
    buildInputs = [ linux-pam shadow ];
    nativeBuildInputs = [ xorg.lndir systemd ];
  } ''
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
        ${escapeShellArg cosmic-files}/share/icons/hicolor/24x24/apps/com.system76.CosmicFiles.svg

    ln -st "$out/usr/bin" -- \
        ${concatMapStringsSep " " (p: "${escapeShellArg p}/bin/*") packages} \
        ${escapeShellArg xdg-desktop-portal}/libexec/xdg-document-portal \
        ${escapeShellArg xdg-desktop-portal-gtk}/libexec/xdg-desktop-portal-gtk
    ln -st "$out/usr/share/dbus-1" -- \
        ${escapeShellArg dbus}/share/dbus-1/session.conf
    ln -st "$out/usr/share/dbus-1/services" -- \
        ${escapeShellArg xdg-desktop-portal-gtk}/share/dbus-1/services/org.freedesktop.impl.portal.desktop.gtk.service

    for pkg in ${escapeShellArgs usrPackages}; do
        # Populate /usr.
        lndir -silent "$pkg" "$out/usr/"
        # lndir does not follow symlinks in the target directory unless
        # the symlink is on the command line and followed by /, so for
        # each symlink there it is necessary to run lndir again.
        for subdir in example share/dbus-1 lib/systemd etc; do
            if [ -d "$pkg/$subdir" ]; then
                lndir -silent "$pkg/$subdir" "$out/usr/$subdir"
            fi
        done
    done

    # Do not link Busybox stuff that is already installed
    for file in ${escapeShellArg spectrum_busybox}/bin/*; do
        output_file=$out/usr/bin/''${file##*/}
        if [ ! -e "$output_file" ]; then
            ln -s -- "$file" "$output_file"
        fi
    done

    # Clean up some unneeded stuff
    rm -- "$out/usr/etc" "$out/usr/lib/systemd" "$out/usr/share/dbus-1" "$out/usr/example" "$out"/usr/lib/*.so*

    # Move udev rules
    mv -- "$out/usr/lib/udev/rules.d" "$out/etc/udev"

    # Tell glibc where the locale archive is
    locale_archive=${escapeShellArg glibcLocales}
    case $locale_archive in
    (*[!0-9A-Za-z._/-]*) echo "Bad locale archive path?" >&2; exit 1;;
    (/*) :;;
    (*) echo "Locale archive not absolute?" >&2; exit 1;;
    esac
    printf '[Manager]
DefaultEnvironment=LOCALE_ARCHIVE=%s PATH=/usr/bin
' "$locale_archive" > "$out/etc/systemd/system.conf.d/zspectrum-locale.conf"

    # Fix the D-Bus config files so they don't include themselves
    for scope in system session; do
        sed -i -- "/\/etc\/dbus-1\/$scope\.conf/d" "$out/etc/dbus-1/$scope.conf"
    done

    # switch_root (used by initramfs) expects init to be at /etc/init,
    # but that just mounts /etc as a writable overlayfs and then executes
    # /sbin/init.
    ln -sf -- ../../${escapeShellArg systemd}/lib/systemd/systemd "$out/usr/bin/init"

    # install PAM stuff where it can be found
    ln -sf -- ../../../${escapeShellArg systemd}/lib/security/pam_systemd.so "$out/usr/lib/security/"

    ${concatStrings (mapAttrsToList (name: path: ''
      ln -s -- ${escapeShellArg path} "$out"/usr/lib/spectrum/vm/${escapeShellArg name}
    '') appvms)}

    # Set up users and groups
    systemd-sysusers --root "$out"

    # Fix up PAM config
    mkdir "$out/etc/pam.d.tmp"
    for i in "$out"/etc/pam.d/*; do sed 's|pam_systemd|${systemd}/lib/security/&|g' < "$i" > "''${i%/*}.tmp/''${i##*/}"; done
    rm -rf "$out/etc/pam.d"
    mv "$out/etc/pam.d.tmp" "$out/etc/pam.d"
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
    inherit appvm firmware kernel nixosAllHardware packagesSysroot systemd;
  };

  meta = with lib; {
    license = licenses.eupl12;
    platforms = platforms.linux;
  };
}
) {}) {}) (_: {})
