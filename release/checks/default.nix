# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix ({ callSpectrumPackage }:

{
  recurseForDerivations = true;

  codespell = callSpectrumPackage ./codespell.nix {};

  deadnix = callSpectrumPackage ./deadnix.nix {};

  doc-links = callSpectrumPackage ./doc-links.nix {};

  doc-anchors = callSpectrumPackage ./doc-anchors.nix {};

  pkg-tests = callSpectrumPackage ./pkg-tests.nix {};

  networking = callSpectrumPackage ./networking {};

  no-roothash = callSpectrumPackage ./no-roothash.nix {};

  reuse = callSpectrumPackage ./reuse.nix {};

  rustfmt = callSpectrumPackage ./rustfmt.nix {};

  shellcheck = callSpectrumPackage ./shellcheck.nix {};

  try = callSpectrumPackage ./try.nix {};

  uncrustify = callSpectrumPackage ./uncrustify.nix {};

  wayland = callSpectrumPackage ./wayland {};
}) (_: {})
