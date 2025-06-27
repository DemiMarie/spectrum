# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix ({ src, lib, runCommand }:

runCommand "spectrum-doc-anchors" {
  src = lib.fileset.toSource {
    root = ../..;
    fileset = src;
  };
} ''
  grep --color=always -r xref:http $src || touch $out
''
) (_: {})
