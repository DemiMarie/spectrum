# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2022 Unikie
# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix ({ src, lib, runCommand, rustfmt }:

runCommand "spectrum-rustfmt" {
  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.intersection src
      (lib.fileset.fileFilter ({ hasExt, ... }: hasExt "rs") ../..);
  };
  nativeBuildInputs = [ rustfmt ];
} ''
  shopt -s globstar
  rustfmt --check --edition 2024 $src/**/*.rs
  touch $out
'') (_: {})
