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
  # Use builtins.fromJSON because it supports \uXXXX escapes.
  # This is the same regex used by check-url.awk in the update VM.
  # The update code is careful to escape any metacharacters, but some
  # simply cannot be made to work.  Concatenating the URL with /SHA256SUMS
  # must append to the path portion of the URL, and the URL must be one
  # that libcurl will accept.
  urlRegex = builtins.fromJSON "\"^[^\\u0001- #?\\u007F]+$\"";
in

# Version is used in many files, so validate it here.
# See https://uapi-group.org/specifications/specs/version_format_specification
# for allowed version strings.
if builtins.match "[[:alnum:]_.~^-]+" finalConfig.version == null then
   builtins.abort ''
     Version ${builtins.toJSON finalConfig.version} has forbidden characters.
     Only ASCII alphanumerics, ".", "_", "~", "^", "+", and "-" are allowed.
     See <https://uapi-group.org/specifications/specs/version_format_specification>.
     ''
else
if builtins.match urlRegex finalConfig.updateUrl == null then
   builtins.abort ''
    Update URL ${builtins.toJSON finalConfig.updateUrl} has forbidden characters.
    Query strings, and fragment specifiers are not supported.
    ASCII control characters and whitespace must be %-encoded.
    ''
else
finalConfig
