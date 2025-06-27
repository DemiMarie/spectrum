# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix ({ srcWithNix, lib, runCommand }:

runCommand "spectrum-whitespace" {
  src = lib.fileset.toSource {
    root = ../..;
    fileset = srcWithNix;
  };
} ''
  grep --color=always --exclude='*.patch' -r "[[:space:]]$" $src || touch $out
''
) (_: {})
