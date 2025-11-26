# SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

import ../../lib/overlay-package.nix [ "gtk3" ] ({ final, super }:

super.gtk3.overrideAttrs ({ patches ? [], ... }: {
  patches = patches ++ [
    (final.fetchpatch {
      url = "https://gitlab.gnome.org/GNOME/gtk/-/commit/8569e206badbee1b27ff0e27316391b8d8c3f987.patch";
      hash = "sha256-OdBhCGtz+3HS8LRhp+GCj3dL4pntybiI9b3A3kc5+OY=";
    })
  ];
}))
