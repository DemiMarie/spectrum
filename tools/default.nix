# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2022-2025 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>

import ../lib/call-package.nix (
{ src, lib, stdenv, fetchCrate, fetchurl, runCommand, buildPackages
, meson, ninja, pkg-config, rustc
, clang-tools, clippy, jq
, dbus
# clang 19 (current nixpkgs default) is too old to support -fwrapv-pointer
, clang_21, libbpf
, buildSupport ? false
, appSupport ? true
, hostSupport ? false
, driverSupport ? false
}:

let
  packageCache = [
    (fetchCrate {
      pname = "itoa";
      version = "1.0.11";
      unpack = false;
      hash = "sha256-SfHxSHMzVFRQDVlhHxz0pLD3hvmsEfQxKnjkzyVmaVs=";
    })
    (fetchurl {
      name = "miniserde-0.1.41.tar.gz";
      url = "https://github.com/dtolnay/miniserde/archive/0.1.41.tar.gz";
      hash = "sha256-2u3mIyslKzImtTJpK4M2nwN1PZJhJPa0ZxUDP/TaCAk=";
    })
    (fetchCrate {
      pname = "proc-macro2";
      version = "1.0.93";
      unpack = false;
      hash = "sha256-YJRqaOX50osNwcIbuKl+59AYqLMi+leDi6McyHjiLZk=";
    })
    (fetchCrate {
      pname = "quote";
      version = "1.0.38";
      unpack = false;
      hash = "sha256-Dk3Mqq+JUU9UbGk93BQPcp+VjCR5GKEzgMzMYHg5Gsw=";
    })
    (fetchCrate {
      pname = "ryu";
      version = "1.0.17";
      unpack = false;
      hash = "sha256-6GaXyRYBmoWIyZtfrDzq107AtLgZcHpoL9TSP6DOG6E=";
    })
    (fetchCrate {
      pname = "syn";
      version = "2.0.58";
      unpack = false;
      hash = "sha256-RM+5PzgHC+7jaz/vfU9aFvJ3UdlLGHtmalzF6bDTBoc=";
    })
    (fetchCrate {
      pname = "unicode-ident";
      version = "1.0.12";
      unpack = false;
      hash = "sha256-M1S5rD+uH/Z1XLbbU2g622YWNPZ1V5Qt6k+s6+wP7ks=";
    })
  ];
in

stdenv.mkDerivation (finalAttrs: {
  name = "spectrum-tools";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.intersection src (lib.fileset.unions ([
      ./meson.build
      ./meson.options
    ] ++ lib.optionals buildSupport [
      ./lseek.c
    ] ++ lib.optionals appSupport [
      ./xdg-desktop-portal-spectrum
    ] ++ lib.optionals hostSupport [
      ./lsvm
      ./start-vmm
      ./subprojects
    ] ++ lib.optionals driverSupport [
      ./xdp-forwarder
    ]));
  };
  sourceRoot = "source/tools";

  depsBuildBuild = lib.optionals hostSupport [ buildPackages.stdenv.cc ];
  nativeBuildInputs = [ meson ninja ]
    ++ lib.optionals (appSupport || driverSupport) [ pkg-config ]
    ++ lib.optionals hostSupport [ rustc ]
    ++ lib.optionals driverSupport [ clang_21 ];
  buildInputs = lib.optionals appSupport [ dbus ] ++ lib.optionals driverSupport [ libbpf ];

  postPatch = lib.optionals hostSupport (lib.concatMapStringsSep "\n" (crate: ''
    mkdir -p subprojects/packagecache
    ln -s ${crate} subprojects/packagecache/${crate.name}
  '') packageCache);

  mesonFlags = [
    (lib.mesonBool "build" buildSupport)
    (lib.mesonBool "app" appSupport)
    (lib.mesonBool "host" hostSupport)
    (lib.mesonBool "driver" driverSupport)
    "-Dhostfsrootdir=/run/virtiofs/virtiofs0"
    "-Dtests=false"
    "-Dunwind=false"
    "-Dwerror=true"
  ];

  # Not supported for target bpf
  hardeningDisable = lib.optionals driverSupport [ "zerocallusedregs" ];

  passthru.tests = {
    clang-tidy = finalAttrs.finalPackage.overrideAttrs (
      { name, src, nativeBuildInputs ? [], ... }:
      {
        name = "${name}-clang-tidy";

        src = lib.fileset.toSource {
          root = ../.;
          fileset = lib.fileset.union (lib.fileset.fromSource src) ../.clang-tidy;
        };

        # clang-tools needs to be before clang, otherwise it will not use
        # the Nix include path correctly and fail to find headers
        nativeBuildInputs = [ clang-tools jq ] ++ nativeBuildInputs;

        buildPhase = ''
          jq -r '.[].file | select(endswith(".c"))' compile_commands.json |
              xargs clang-tidy --warnings-as-errors='*'
          touch $out
          exit 0
        '';
      }
    );

    tests = finalAttrs.finalPackage.overrideAttrs (
      { name, mesonFlags ? [], ... }:
      {
        name = "${name}-tests";

        mesonFlags = mesonFlags ++ [
          "-Dunwind=true"
          "-Dtests=true"
        ];

        doCheck = true;
      }
    );
  } // lib.optionalAttrs hostSupport {
    clippy = finalAttrs.finalPackage.overrideAttrs (
      { name, nativeBuildInputs ? [], ... }:
      {
        name = "${name}-clippy";
        nativeBuildInputs = nativeBuildInputs ++ [ clippy ];
        dontBuild = true;
        doCheck = true;
        dontUseMesonCheck = true;
        checkTarget = "clippy";
        installPhase = ''touch $out && exit 0'';
      }
    );
  };

  meta = with lib; {
    description = "First-party Spectrum programs";
    license = licenses.eupl12;
    maintainers = with maintainers; [ qyliss ];
    platforms = platforms.linux;
  };
})
) (_: {})

