# SPDX-FileCopyrightText: 2024-2025 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

import ../../lib/call-package.nix (
{ src, lib, rustPlatform }:

rustPlatform.buildRustPackage {
  name = "mount-flatpak";

  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.intersection src ./.;
  };
  sourceRoot = "source/tools/mount-flatpak";

  cargoLock.lockFile = ./Cargo.lock;

  env = {
    MOUNT_FLATPAK_CONFIG_PATH = "${placeholder "out"}/share/spectrum/flatpak-config";
  };

  postInstall = ''
    install -Dm 0755 config $MOUNT_FLATPAK_CONFIG_PATH
  '';
}) (_: {})
