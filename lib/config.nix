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

  # Only allow unreserved characters, : (for port numbers), /, and %-encoding.
  # The rest of the code is allowed to assume that these are the only characters
  # in the update URL.
  # Do not use [:alnum:] or [:hexdigit:] as they depend on the locale in POSIX.
  # Query strings and fragment identifiers break appending
  # /SHA256SUMS and /SHA256SUMS.gpg to a URL.
  # [, ], {, and } would cause globbing in curl.
  url-regex = "^https?://([ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789:./~-]|%[ABCDEFabcdef0123456789]{2})+$";
  update-url = finalConfig.update-url;

  # Only allow a numeric version for now.
  number_re = "(0|[1-9][0-9]{0,2})";
  version_re = "^(${number_re}\\.){2}${number_re}$";
in
  if !builtins.isString update-url then
    builtins.abort "Update URL must be a string, not ${builtins.typeOf update-url}"
  else if builtins.match "^https?://.*" update-url == null then
    builtins.abort "Update URL ${builtins.toJSON update-url} has unsupported scheme (not https:// or http://) or is invalid"
  else if builtins.match url-regex update-url == null then
    builtins.abort "Update URL ${builtins.toJSON update-url} has forbidden characters"
  else if builtins.substring (builtins.stringLength update-url - 1) 1 update-url == "/" then
    builtins.abort "Update URL ${builtins.toJSON update-url} must not end with /"
  else if !builtins.isString finalConfig.version then
    builtins.abort "Version must be a string, not ${builtins.typeOf finalConfig.version}"
  else if builtins.match version_re finalConfig.version == null then
    builtins.abort "Version ${builtins.toJSON finalConfig.version} is invalid"
  else if !builtins.isPath finalConfig.update-signing-key then
    builtins.abort "Update verification key file is of type ${builtins.typeOf finalConfig.update-signing-key}, not path"
  else
    finalConfig // {
      update-signing-key = builtins.path {
        name = "signing-key";
        path = finalConfig.update-signing-key;
      };
    }
