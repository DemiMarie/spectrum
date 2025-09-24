# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023-2024 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix (
{ callSpectrumPackage, lseek, lib }:

{
  recurseForDerivations = true;

  lseek = lib.recurseIntoAttrs lseek.tests;

  integration = lib.recurseIntoAttrs (callSpectrumPackage ./integration {}).tests;

  tools = lib.recurseIntoAttrs (callSpectrumPackage ../../tools {
    appSupport = true;
    hostSupport = true;
    driverSupport = true;
  }).tests;
}) (_: {})
