# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2022-2025 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix (
{ src, lib, stdenv, fetchCrate, fetchurl, buildPackages
, meson, ninja, rustc, clang-tools, clippy, run-spectrum-vm
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
  name = "start-vmm";

  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.intersection src ./.;
  };
  sourceRoot = "source/host/start-vmm";

  depsBuildBuild = [ buildPackages.stdenv.cc ];
  nativeBuildInputs = [ meson ninja rustc ];

  postPatch = lib.concatMapStringsSep "\n" (crate: ''
    mkdir -p subprojects/packagecache
    ln -s ${crate} subprojects/packagecache/${crate.name}
  '') packageCache;

  mesonFlags = [ "-Dtests=false" "-Dunwind=false" "-Dwerror=true" ];

  passthru.tests = {
    clang-tidy = finalAttrs.finalPackage.overrideAttrs (
      { src, nativeBuildInputs ? [], ... }:
      {
        src = lib.fileset.toSource {
          root = ../..;
          fileset = lib.fileset.union (lib.fileset.fromSource src) ../../.clang-tidy;
        };

        nativeBuildInputs = nativeBuildInputs ++ [ clang-tools ];

        buildPhase = ''
          clang-tidy --warnings-as-errors='*' -p . ../*.c ../*.h
          touch $out
          exit 0
        '';
      }
    );
    clippy = finalAttrs.finalPackage.overrideAttrs (
      { name, nativeBuildInputs ? [], ... }:
      {
        name = "${name}-clippy";
        nativeBuildInputs = nativeBuildInputs ++ [ clippy ];
        preConfigure = ''
          # It's not currently possible to enable warnings only for
          # non-subprojects without enumerating the subprojects.
          # https://github.com/mesonbuild/meson/issues/9398#issuecomment-954094750
          mesonFlagsArray+=(
              -Dproc-macro2:werror=false
              -Dproc-macro2:warning_level=0
              -Dquote:werror=false
              -Dquote:warning_level=0
              -Dryu:werror=false
              -Dryu:warning_level=0
              -Dsyn:werror=false
              -Dsyn:warning_level=0
          )
        '';
        dontBuild = true;
        doCheck = true;
        dontUseMesonCheck = true;
        checkTarget = "clippy";
        installPhase = ''touch $out && exit 0'';
      }
    );

    run = run-spectrum-vm.override { start-vmm = finalAttrs.finalPackage; };

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
  };

  meta = {
    mainProgram = "start-vmm";
  };
})
) (_: {})
