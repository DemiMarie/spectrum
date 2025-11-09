# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix ({ testers }: testers.nixosTest ({ ... }: {
  name = "spectrum-test-installer";
  enableOCR = true;

  nodes = {
    machine = ../installer/configuration.nix;
  };

  testScript = ''
    start_all()
    machine.wait_for_text("Spectrum")
  '';
})) (_: {})
