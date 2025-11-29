# SPDX-FileCopyrightText: 2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>
# SPDX-License-Identifier: MIT

import ../../lib/call-package.nix (
{ src, lib, rustPlatform }:

rustPlatform.buildRustPackage {
  name = "spectrum-router";

  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.intersection src ./.;
  };
  sourceRoot = "source/tools/router";

  cargoLock.lockFile = ./Cargo.lock;
}) (_: {})
