# SPDX-FileCopyrightText: 2021-2022 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

{ runCommand, e2fsprogs }:

runCommand "ext.ext4" {
  nativeBuildInputs = [ e2fsprogs ];
  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
} ''
  mkfs.ext4 $out 16T
  resize2fs -M $out
''
