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

  update-url = finalConfig.update-url;

  # See https://uapi-group.org/specifications/specs/version_format_specification
  # for allowed version strings.  Also impose the following restrictions:
  # - Do not allow '+'.  It is equivalent to '_' and SHOULD NOT be used.
  # - Require the first part to be a version number of the form MAJOR.MINOR.PATCH,
  #   where all components fit in an int and have no leading zeros.
  # - If there is anything after PATCH, require it to be something that has an effect
  #   (not '_').
  number-re = "(0|[1-9][0-9]{0,8})";
  version-number-re = "${number-re}\\.${number-re}\\.${number-re}";
  version-re = version-number-re + "([[:alpha:]_.~^-][[:alnum:]_.~^-]*)?";
  why-version-invalid = version:
    # Version number is invalid or unsupported.  Do some checks to provide a more helpful error message.
    # Keep these separate to reduce evaluation time.
    if version == "" then
      builtins.abort "Version is empty string!"
    else if builtins.match "[[:alnum:]_.~^-]+" == null then
      builtins.abort
        ''
        Version ${builtins.toJSON version} has forbidden characters.
        Only ASCII alphanumerics, ".", "_", "~", "^", and "-" are allowed.
        ''
    else if builtins.match "[[:digit:]]+\\.[[:digit:]]+\\.[[:digit:]].*" finalConfig.version == null then
      builtins.abort "Version ${version} doesn't start with MAJOR.MINOR.PATCH"
    else if builtins.match version-number-re finalConfig.version == null then
      builtins.abort "Version ${version} has a version number with an excess leading zero or greater than 999999999"
    else
      builtins.abort "Version ${version} has an alphanumeric character after the patch version";
in

if builtins.match version-re finalConfig.version == null then
  why-version-invalid finalConfig.version
else
  finalConfig // {
    update-signing-key = builtins.path {
      name = "signing-key";
      path = finalConfig.update-signing-key;
    };
  }
