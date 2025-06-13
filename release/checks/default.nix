# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix ({ callSpectrumPackage }:

{
  recurseForDerivations = true;

  codespell = callSpectrumPackage ./codespell.nix {};

  deadnix = callSpectrumPackage ./deadnix.nix {};

  doc-links = callSpectrumPackage ./doc-links.nix {};

  doc-anchors = callSpectrumPackage ./doc-anchors.nix {};

  integration = callSpectrumPackage ./integration {};

  pkg-tests = callSpectrumPackage ./pkg-tests.nix {};

  no-roothash = callSpectrumPackage ./no-roothash.nix {};

  reuse = callSpectrumPackage ./reuse.nix {};

  rustfmt = callSpectrumPackage ./rustfmt.nix {};

  shellcheck = callSpectrumPackage ./shellcheck.nix {};

  uncrustify = callSpectrumPackage ./uncrustify.nix {};

  wayland = callSpectrumPackage ./wayland {};

  whitespace = callSpectrumPackage ./whitespace.nix {};
}) (_: {})
