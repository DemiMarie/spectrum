# SPDX-FileCopyrightText: 2023-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

{ ... } @ args:

let
  config = import ../lib/config.nix args;
  pkgs = import ./overlaid.nix ({ elaboratedConfig = config; } // args);

  inherit (pkgs.lib) cleanSource fileset makeScope optionalAttrs sourceByRegex;

  subprojects =
    project:
    let dir = project + "/subprojects"; in
    fileset.difference dir (fileset.fromSource (sourceByRegex dir [
      ".*\.wrap"
      "packagefiles(/.*)?"
    ]));

  makeScopeWithSplicing = pkgs: pkgs.makeScopeWithSplicing' {
    otherSplices = {
      selfBuildBuild = makeScope pkgs.pkgsBuildBuild.newScope scope;
      selfBuildHost = makeScope pkgs.pkgsBuildHost.newScope scope;
      selfBuildTarget = makeScope pkgs.pkgsBuildTarget.newScope scope;
      selfHostHost = makeScope pkgs.pkgsHostHost.newScope scope;
      selfTargetTarget = optionalAttrs (pkgs.pkgsTargetTarget ? newScope)
        (makeScope pkgs.pkgsTargetTarget.newScope scope);
    };
    f = scope;
  };

  scope = self: let pkgs = self.callPackage ({ pkgs }: pkgs) {}; in {
    inherit config;

    callSpectrumPackage =
      path: (import path { inherit (self) callPackage; }).override;

    lseek = self.callSpectrumPackage ../tools/lseek {};
    rootfs = self.callSpectrumPackage ../host/rootfs {};
    spectrum-app-tools = self.callSpectrumPackage ../tools {};
    spectrum-host-tools = self.callSpectrumPackage ../tools {
      appSupport = false;
      hostSupport = true;
    };
    xdg-desktop-portal-spectrum-host =
      self.callSpectrumPackage ../tools/xdg-desktop-portal-spectrum-host {};

    # Packages from the overlay, so it's possible to build them from
    # the CLI easily.
    inherit (pkgs) cloud-hypervisor dbus;

    pkgsStatic = makeScopeWithSplicing pkgs.pkgsStatic;

    srcWithNix = fileset.difference
      (fileset.fromSource (cleanSource ../.))
      (fileset.unions ([
        (subprojects ../tools)
      ] ++ map fileset.maybeMissing [
        ../Documentation/.jekyll-cache
        ../Documentation/_site
        ../host/initramfs/build
        ../host/rootfs/build
        ../img/app/build
        ../release/live/build
        ../vm/sys/net/build
      ]));

    src = fileset.difference
      self.srcWithNix
      (fileset.fileFilter ({ hasExt, ... }: hasExt "nix") ../.);
  };
in

makeScopeWithSplicing pkgs
