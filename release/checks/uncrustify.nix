# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2022 Unikie
# SPDX-FileCopyrightText: 2023-2024 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix ({ src, lib, runCommand, uncrustify }:

runCommand "spectrum-uncrustify" {
  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.intersection src
      (lib.fileset.fileFilter
        ({ hasExt, ... }: hasExt "c" || hasExt "h") ../..);
  };
  nativeBuildInputs = [ uncrustify ];
} ''
  shopt -s globstar
  uncrustify -c ${../../uncrustify.cfg} --check $src/**/*.[ch]
  touch $out
'') (_: {})
