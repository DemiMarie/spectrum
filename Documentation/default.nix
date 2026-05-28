# SPDX-FileCopyrightText: 2022-2023 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie
# SPDX-License-Identifier: MIT

import ../lib/call-package.nix

({ callSpectrumPackage, src, lib, stdenvNoCC }:

stdenvNoCC.mkDerivation {
  name = "spectrum-docs";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.intersection src ./.;
  };
  sourceRoot = "source/Documentation";

  buildPhase = ''
    runHook preBuild
    jekyll build --disable-disk-cache -d $out
    runHook postBuild
  '';

  # The fixup phase would move `doc` to `share/doc` and we don't want that.
  dontFixup = true;
  dontInstall = true;

  nativeBuildInputs = [ (callSpectrumPackage ./jekyll.nix {}) ];
}) (_: {})
