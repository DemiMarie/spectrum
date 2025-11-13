# SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

import ../../lib/overlay-package.nix [ "skawarePackages" ] ({ final, super }:

super.skawarePackages.overrideScope (_: prev: {
  mdevd = prev.mdevd.overrideAttrs ({ patches ? [], ... }: {
    patches = patches ++ [
      (final.fetchpatch {
        url = "https://git.skarnet.org/cgi-bin/cgit.cgi/mdevd/patch/?id=252f241e425bf09ddfb4a824e40403f40da0da1e";
        hash = "sha256-0tEC+yJGyPapsxBqzBXPztF3bl7OwjVAGjhNXtwZQ0g=";
      })
    ];
  });
}))
