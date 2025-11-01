# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

let
  raw_version = builtins.readFile ../version;
  version_length = builtins.stringLength raw_version - 1;
  version = builtins.substring 0 version_length raw_version;
  number_re = "(0|[1-9][0-9]{0,2})";
in
if version_length < 0 || builtins.substring version_length 1 raw_version != "\n" then
  builtins.abort "Version file missing trailing newline (contents ${builtins.toJSON raw_version})"
else if builtins.match "^(${number_re}\\.){2}${number_re}$" version == null then
  builtins.abort "Version ${builtins.toJSON version} is invalid"
else
  version
