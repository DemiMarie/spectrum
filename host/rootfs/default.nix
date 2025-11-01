# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2025 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie

import ../../lib/call-package.nix (
{ callSpectrumPackage, spectrum-build-tools, src
, pkgsMusl, pkgsStatic, linux_latest
, config
}:
pkgsStatic.callPackage (

{ spectrum-host-tools
, lib, stdenvNoCC, nixos, runCommand, writeClosure, erofs-utils, s6-rc
, busybox, cloud-hypervisor, cryptsetup, dbus, execline, inkscape
, iproute2, inotify-tools, jq, mdevd, s6, s6-linux-init, socat
, util-linuxMinimal, virtiofsd, xorg, xdg-desktop-portal-spectrum-host
, btrfs-progs
}:

let
  inherit (nixosAllHardware.config.hardware) firmware;
  inherit (lib)
    concatMapStringsSep concatStrings escapeShellArgs fileset optionalAttrs
    mapAttrsToList systems trivial;

  pkgsGui = pkgsMusl.extend (
    _: super:
    (optionalAttrs (systems.equals pkgsMusl.stdenv.hostPlatform super.stdenv.hostPlatform) {
      flatpak = super.flatpak.override {
        withMalcontent = false;
      };
    })
  );

  foot = pkgsGui.foot.override { allowPgo = false; };

  packages = [
    cloud-hypervisor cryptsetup dbus execline inotify-tools iproute2
    jq mdevd s6 s6-linux-init s6-rc socat spectrum-host-tools
    virtiofsd xdg-desktop-portal-spectrum-host
    btrfs-progs

    (busybox.override {
      # Use a separate file as it is a bit too big.
      extraConfig = builtins.readFile ./busybox-config;
    })

  # Take kmod from pkgsGui since we use pkgsGui.kmod.lib below anyway.
  ] ++ (with pkgsGui; [ cosmic-files crosvm foot fuse3 kmod ]);


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
    appvm kernel.modules firmware netvm
  ] ++ (with pkgsGui; [ dejavu_fonts kmod.lib mesa westonLite systemd ]);

  appvms = {
    appvm-firefox = callSpectrumPackage ../../vm/app/firefox.nix {};
    appvm-foot = callSpectrumPackage ../../vm/app/foot.nix {};
    appvm-gnome-text-editor = callSpectrumPackage ../../vm/app/gnome-text-editor.nix {};
    appvm-updates = callSpectrumPackage ../../vm/app/updates.nix {};
  };

  packagesSysroot = runCommand "packages-sysroot" {
    depsBuildBuild = [ inkscape ];
    nativeBuildInputs = [ xorg.lndir ];
    env = {
      VERSION = config.version;
      UPDATE_URL = config.update-url;
    };
    src = fileset.toSource {
      root = ./.;
      fileset = fileset.intersection src (fileset.unions [
        ./vm-sysupdate.d
        ./os-release.in
        ./updatevm-url-env
      ]);
    };
  } ''
    mkdir -p $out/usr/bin $out/usr/share/dbus-1/services \
      $out/usr/share/icons/hicolor/20x20/apps

    # lndir silently ignores existing links, so run it before ln
    # so that ln catches any duplicates.
    for pkg in ${escapeShellArgs usrPackages}; do
        lndir -ignorelinks -silent "$pkg" "$out/usr"
    done

    # If systemd-pull is missing systemd-sysupdate will fail with a
    # very confusing error message.
    for i in sysupdate pull; do
        if ! cat -- "$out/usr/lib/systemd/systemd-$i" > /dev/null; then
            echo "link to systemd-$i didn't get installed" >&2
            exit 1
        fi
    done

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

    mkdir -p -- "$out/etc/updatevm/sysupdate.d"
    substitute "$src/os-release.in" "$out/etc/os-release" --subst-var VERSION
    for d in "$src/vm-sysupdate.d"/*.transfer; do
      result_file=''${d#"$src/vm-sysupdate.d/"}
      substitute "$d" "$out/etc/updatevm/sysupdate.d/$result_file" --subst-var UPDATE_URL
    done
    substitute "$src/updatevm-url-env" "$out/etc/updatevm/url-env" --subst-var UPDATE_URL

    ln -st "$out/usr/bin" ${util-linuxMinimal}/bin/*

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
      ../../lib/kcmdline-utils.mk
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
    UPDATE_SIGNING_KEY = config.update-signing-key;
  };

  makeFlags = [ "dest=$(out)" ];

  dontInstall = true;

  enableParallelBuilding = true;

  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
  dontFixup = true;

  passthru = {
    inherit appvm firmware kernel nixosAllHardware packagesSysroot pkgsGui;
  };

  meta = with lib; {
    license = licenses.eupl12;
    platforms = platforms.linux;
  };
}
) {}) (_: {})
