# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix ({ src, lib, runCommand, shfmt }:

runCommand "spectrum-shfmt" {
  src = lib.fileset.toSource {
    root = ../..;
    fileset = src;
  };
  nativeBuildInputs = [ shfmt ];
} ''
  shfmt -d $src
  touch $out
'') (_: {})
