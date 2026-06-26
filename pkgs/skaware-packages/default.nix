# SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

import ../../lib/overlay-package.nix [ "skawarePackages" ] ({ final, super }:

super.skawarePackages.overrideScope (_: prev: {
  s6 = prev.s6.overrideAttrs ({ patches ? [], ... }: {
    patches = patches ++ [
      (final.fetchpatch {
        url = "https://github.com/skarnet/s6/commit/c3a8ef7034fb2bc02f35381a8970ac026822a810.patch";
        hash = "sha256-lgCoPbEYru6/a2bpVpLsZ2Rq2OHhNVs0lDgFO/df1Aw=";
      })
    ];
  });

  mdevd = prev.mdevd.overrideAttrs ({ patches ? [], ... }: {
    patches = patches ++ [
      (final.fetchpatch {
        url = "https://github.com/skarnet/mdevd/commit/252f241e425bf09ddfb4a824e40403f40da0da1e.patch";
        hash = "sha256-0tEC+yJGyPapsxBqzBXPztF3bl7OwjVAGjhNXtwZQ0g=";
      })
    ];
  });
}))
