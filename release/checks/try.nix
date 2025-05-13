# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023-2024 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix (
{ callSpectrumPackage, lib, nixosTest, path }:

lib.fix (self: nixosTest ({ pkgs, stdenv, mtools, ... }:

let
  live = callSpectrumPackage ../live {};

  inherit (import (path + /nixos/lib/qemu-common.nix) { inherit lib pkgs; })
    qemuBinary qemuSerialDevice;
in {
  name = "try-spectrum-test";
  nodes = {};

  testScript = ''
    import shlex

    flags = "${qemuBinary self.config.qemu.package} " + " ".join(map(shlex.quote, [
      "-m", "1G",
      "-device", "qemu-xhci",
      "-device", "usb-storage,drive=drive1,removable=true",
      "-drive", "file=${self.config.qemu.package}/share/qemu/edk2-${stdenv.hostPlatform.qemuArch}-code.fd,format=raw,if=pflash,readonly=on",
      "-drive", "file=${live},id=drive1,format=raw,if=none,readonly=on",
      "-smbios", "type=11,value=io.systemd.stub.kernel-cmdline-extra=console=${qemuSerialDevice} panic=-1",
    ]))

    machine = create_machine(flags)

    machine.start()
    machine.wait_for_console_text("EXT4-fs \\(sda4\\): mounted filesystem")
    machine.crash()
  '';
}))) (_: {})
