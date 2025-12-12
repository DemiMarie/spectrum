# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2025 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie

import ../../lib/call-package.nix (
{ callSpectrumPackage, config, spectrum-build-tools
, src, pkgsMusl, inkscape, linux_latest, xorg
}:
pkgsMusl.callPackage (

{ spectrum-host-tools, spectrum-router
, lib, stdenvNoCC, nixos, runCommand, writeClosure, erofs-utils, s6-rc
, btrfs-progs, bubblewrap, busybox, cloud-hypervisor, cosmic-files
, crosvm, cryptsetup, dejavu_fonts, dbus, execline, foot, fuse3
, iproute2, inotify-tools, jq, kmod, lvm2, mdevd, mesa, mount-flatpak
, s6, s6-linux-init, shadow, socat, systemd, util-linuxMinimal, virtiofsd
, westonLite, xdg-desktop-portal, xdg-desktop-portal-gtk
, xdg-desktop-portal-spectrum-host
}:

let
  inherit (nixosAllHardware.config.hardware) firmware;
  inherit (lib)
    concatMapStringsSep concatStrings escapeShellArgs fileset mapAttrsToList
    trivial;

  packages = [
    btrfs-progs bubblewrap cloud-hypervisor cosmic-files crosvm cryptsetup dbus
    execline fuse3 inotify-tools iproute2 jq kmod mdevd mount-flatpak s6
    s6-linux-init s6-rc shadow socat spectrum-host-tools spectrum-router
    virtiofsd xdg-desktop-portal-spectrum-host

    (foot.override { allowPgo = false; })

    (busybox.override {
      # Use a separate file as it is a bit too big.
      extraConfig = builtins.readFile ./busybox-config;
    })

    (util-linuxMinimal.overrideAttrs ({ configureFlags ? [], ... }: {
      # Conflicts with shadow.
      configureFlags = configureFlags ++ [ "--disable-nologin" ];
    }))
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
  #
  # kmod.lib is dlopen()ed by systemd-udevd via libsystemd-shared.so.
  # It doesn't get picked up from libsystemd-shared.so's RUNPATH due to
  # https://inbox.vuxu.org/musl/20251017-dlopen-use-rpath-of-caller-dso-v1-1-46c69eda1473@iscas.ac.cn/
  usrPackages = [
    appvm dejavu_fonts firmware kernel.modules kmod.lib lvm2 mesa
    netvm systemd westonLite
  ];

  appvms = {
    appvm-firefox = callSpectrumPackage ../../vm/app/firefox.nix {};
    appvm-foot = callSpectrumPackage ../../vm/app/foot.nix {};
    appvm-gnome-text-editor = callSpectrumPackage ../../vm/app/gnome-text-editor.nix {};
    appvm-systemd-sysupdate = callSpectrumPackage ../../vm/app/systemd-sysupdate {};
  };

  packagesSysroot = runCommand "packages-sysroot" {
    depsBuildBuild = [ inkscape ];
    nativeBuildInputs = [ xorg.lndir ];
    src = builtins.path { name = "os-release"; path = ./os-release.in; };
  } ''
    mkdir -p $out/usr/bin $out/usr/share/dbus-1/services \
      $out/usr/share/icons/hicolor/20x20/apps

    # lndir silently ignores existing links, so run it before ln
    # so that ln catches any duplicates.
    for pkg in ${escapeShellArgs usrPackages}; do
        lndir -ignorelinks -silent "$pkg" "$out/usr"
    done

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

    ${concatStrings (mapAttrsToList (name: path: ''
      ln -s ${path} $out/usr/lib/spectrum/vm/${name}
    '') appvms)}
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

  nativeBuildInputs = [ cryptsetup erofs-utils spectrum-build-tools s6-rc ];

  env = {
    PACKAGES = runCommand "packages" {} ''
      printf "%s\n/\n" ${packagesSysroot} >$out
      sed p ${writeClosure [ packagesSysroot] } >>$out
    '';
    UPDATE_SIGNING_KEY = builtins.path {
      name = "signing-key";
      path = config.updateSigningKey;
    };
    UPDATE_URL = config.updateUrl;
    VERSION = config.version;
  };

  # The Makefile uses $(ROOT_FS), not $(dest), so it can share code
  # with other Makefiles that also use this variable.
  makeFlags = [ "ROOT_FS=$(out)" ];

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
) {}) (_: {})
