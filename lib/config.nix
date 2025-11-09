# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>
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

# Version is used in many files, so validate it here.
# See https://uapi-group.org/specifications/specs/version_format_specification
# for allowed version strings.
if builtins.match "[[:alnum:]_.~^-]+" finalConfig.version == null then
   builtins.abort ''
     Version ${builtins.toJSON finalConfig.version} has forbidden characters.
     Only ASCII alphanumerics, ".", "_", "~", "^", "+", and "-" are allowed.
     ''
else
  finalConfig
