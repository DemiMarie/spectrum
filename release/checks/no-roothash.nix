# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023-2024 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix (
{ callSpectrumPackage, rootfs, lib, testers, path }:

lib.fix (self: testers.nixosTest ({ pkgs, stdenv, ... }:

let
  initramfs = callSpectrumPackage ../../host/initramfs {};

  inherit (import (path + /nixos/lib/qemu-common.nix) { inherit lib pkgs; })
    qemuBinary qemuSerialDevice;
in {
  name = "spectrum-test-initramfs-no-roothash";
  nodes = {};

  testScript = ''
    import shlex

    flags = "${qemuBinary self.config.qemu.package} " + " ".join(map(shlex.quote, [
      "-m", "512",
      "-kernel", "${rootfs.kernel}/${stdenv.hostPlatform.linux-kernel.target}",
      "-initrd", "${initramfs}",
      "-append", "console=${qemuSerialDevice} panic=-1",
    ]))

    machine = create_machine(flags)

    machine.start()
    machine.wait_for_console_text("roothash not set")
  '';
}))) (_: {})
