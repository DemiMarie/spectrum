# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

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
  if !builtins.isList (builtins.match "^[A-Za-z0-9.~^+-]+$" config.version) then
    builtins.abort "Version string ${builtins.toJSON config.version} is invalid (did you use _ instead of +?)"
  else
    finalConfig
