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
        CONFIG_ACPID n
        CONFIG_ARP n
        CONFIG_ARPING n
        CONFIG_BEEP n
        CONFIG_BLKDISCARD n
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
        CONFIG_HALT n
        CONFIG_HTTPD n
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
        CONFIG_POWEROFF n
        CONFIG_PSCAN n
        CONFIG_REBOOT n
        CONFIG_REFORMMIME n
        CONFIG_RMMOD n
        CONFIG_ROUTE n
        CONFIG_RUNSV n
        CONFIG_RUNSVDIR n
        CONFIG_SENDMAIL n
        CONFIG_SETARCH n
        CONFIG_SHELL_HUSH n
        CONFIG_SHUTDOWN n
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

    # scripts/make-erofs will re-add this
    rm -f "$out/usr/sbin" "$out/sbin" "$out/bin" "$out/lib"
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
