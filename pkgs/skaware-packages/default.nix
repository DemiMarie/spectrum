# SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

import ../../lib/overlay-package.nix [ "skawarePackages" ] ({ final, super }:

super.skawarePackages.overrideScope (_: prev: {
  s6 = prev.s6.overrideAttrs ({ patches ? [], ... }: {
    patches = patches ++ [
      (final.fetchpatch {
        url = "https://git.skarnet.org/cgi-bin/cgit.cgi/s6/patch/?id=c3a8ef7034fb2bc02f35381a8970ac026822a810";
        hash = "sha256-lgCoPbEYru6/a2bpVpLsZ2Rq2OHhNVs0lDgFO/df1Aw=";
      })
    ];
  });

  mdevd = prev.mdevd.overrideAttrs ({ patches ? [], ... }: {
    patches = patches ++ [
      (final.fetchpatch {
        url = "https://git.skarnet.org/cgi-bin/cgit.cgi/mdevd/patch/?id=252f241e425bf09ddfb4a824e40403f40da0da1e";
        hash = "sha256-0tEC+yJGyPapsxBqzBXPztF3bl7OwjVAGjhNXtwZQ0g=";
      })
    ];
  });
}))
