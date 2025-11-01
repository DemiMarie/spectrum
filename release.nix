# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2022-2023 Alyssa Ross <hi@alyssa.is>

# This file is built to populate the binary cache.

import lib/call-package.nix ({ callSpectrumPackage }: {
  doc = callSpectrumPackage ./Documentation {};

  checks = callSpectrumPackage release/checks {};

  updates = callSpectrumPackage release/update.nix {};

  combined = callSpectrumPackage release/combined/run-vm.nix {};
}) (_: {})
