# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021, 2023 Alyssa Ross <hi@alyssa.is>

import ../lib/call-package.nix ({ callSpectrumPackage, clang-tools, clippy, rustfmt }:

(callSpectrumPackage ./. {
  appSupport = true;
  hostSupport = true;
}).overrideAttrs ({ hardeningDisable ? [], nativeBuildInputs ? [], ... }: {
  # Not compatible with Meson's default -O0.
  hardeningDisable = hardeningDisable ++ [ "fortify" ];

  nativeBuildInputs = nativeBuildInputs ++ [ clang-tools clippy rustfmt ];
})) (_: {})
