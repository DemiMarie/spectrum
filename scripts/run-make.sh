#!/usr/bin/env -S bash --
# SPDX-License-Identifier: CC0-1.0
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
set -eu
case $0 in (/*) cd "${0%/*}/";; (*/*) cd "./${0%/*}";; esac
if [ ! -f shell.nix ] || [ ! -f Makefile ]; then
  echo "Must have a shell.nix and a Makefile" >&2
  exit 1
fi
cmd='exec make'
for i; do cmd+=" '"${i//\'/\'\\\'\'}\'; done
exec nix-shell --run "$cmd"
