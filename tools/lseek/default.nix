# SPDX-FileCopyrightText: 2023-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

import ../../lib/call-package.nix ({ src, pkgsStatic }:
pkgsStatic.callPackage ({ lib, stdenv, clang-tools }:

stdenv.mkDerivation (finalAttrs: {
  name = "lseek";

  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.difference
      (lib.fileset.intersection src ./.)
      (lib.fileset.maybeMissing ./lseek);
  };
  sourceRoot = "source/tools/lseek";

  makeFlags = [ "prefix=$(out)" ];

  enableParallelBuilding = true;

  passthru.tests = {
    clang-tidy = finalAttrs.finalPackage.overrideAttrs (
      { name, src, nativeBuildInputs ? [], ... }:
      {
        name = "${name}-clang-tidy";

        src = lib.fileset.toSource {
          root = ../..;
          fileset = lib.fileset.union (lib.fileset.fromSource src) ../../.clang-tidy;
        };

        nativeBuildInputs = nativeBuildInputs ++ [ clang-tools ];

        buildPhase = ''
          clang-tidy --warnings-as-errors='*' lseek.c --
          touch $out
          exit 0
        '';
      }
    );
  };

  meta = with lib; {
    description = "Seek an open file descriptor, then exec.";
    license = licenses.eupl12;
    maintainers = with maintainers; [ qyliss ];
    platforms = platforms.unix;
  };
})

) {}) (_: {})
