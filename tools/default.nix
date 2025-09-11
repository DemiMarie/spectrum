# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2022-2025 Alyssa Ross <hi@alyssa.is>

import ../lib/call-package.nix (
{ src, lib, stdenv, fetchCrate, fetchurl, runCommand, buildPackages
, meson, ninja, pkg-config, rustc
, clang-tools, clippy
, dbus
, guestSupport ? true
, hostSupport ? false
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
      ./meson_options.txt
    ] ++ lib.optionals guestSupport [
      ./xdg-desktop-portal-spectrum
    ] ++ lib.optionals hostSupport [
      ./lsvm
      ./start-vmm
      ./subprojects
      ./sd-notify-adapter
    ]));
  };
  sourceRoot = "source/tools";

  depsBuildBuild = lib.optionals hostSupport [ buildPackages.stdenv.cc ];
  nativeBuildInputs = [ meson ninja ]
    ++ lib.optionals guestSupport [ pkg-config ]
    ++ lib.optionals hostSupport [ rustc ];
  buildInputs = lib.optionals guestSupport [ dbus ];

  postPatch = lib.optionals hostSupport (lib.concatMapStringsSep "\n" (crate: ''
    mkdir -p subprojects/packagecache
    ln -s ${crate} subprojects/packagecache/${crate.name}
  '') packageCache);

  mesonFlags = [
    (lib.mesonBool "guest" guestSupport)
    (lib.mesonBool "host" hostSupport)
    "-Dhostfsrootdir=/run/virtiofs/virtiofs0"
    "-Dtests=false"
    "-Dunwind=false"
    "-Dwerror=true"
  ];

  passthru.tests = {
    clang-tidy = finalAttrs.finalPackage.overrideAttrs (
      { name, src, nativeBuildInputs ? [], ... }:
      {
        name = "${name}-clang-tidy";

        src = lib.fileset.toSource {
          root = ../.;
          fileset = lib.fileset.union (lib.fileset.fromSource src) ../.clang-tidy;
        };

        nativeBuildInputs = nativeBuildInputs ++ [ clang-tools ];

        buildPhase = ''
          clang-tidy --warnings-as-errors='*' ../**/*.c
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

