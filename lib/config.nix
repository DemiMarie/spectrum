# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

let
  customConfigPath = builtins.tryEval <spectrum-config>;
in

{ config ?
  if customConfigPath.success then import customConfigPath.value
  else if builtins.pathExists ../config.nix then import ../config.nix
  else {}
}:

let
  default = import ../lib/config.default.nix;

  callConfig = config: if builtins.typeOf config == "lambda" then config {
    inherit default;
  } else config;
  finalConfig = default // callConfig config;
in
  finalConfig // {
    update-signing-key = builtins.path {
      name = "signing-key";
      path = finalConfig.update-signing-key;
    };
  }
