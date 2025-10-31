# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

import ../lib/call-package.nix ({ cryptsetup, runCommand, rootfs }:
runCommand "spectrum-verity" {
  nativeBuildInputs = [ cryptsetup ];
  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
  dontFixup = true;
} ''
  mkdir -- "$out"
  veritysetup format -- ${rootfs} "$out/rootfs.verity.superblock" |
      awk -F ':[[:blank:]]*' '$1 == "Root hash" {print $2; exit}' \
      > "$out/rootfs.verity.roothash"
  ''
) (_: {})
