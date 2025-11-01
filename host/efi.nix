# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

import ../lib/call-package.nix (
{ bash, callSpectrumPackage, cryptsetup, runCommand
, stdenv, systemdUkify, rootfs, verity
}:
let
  initramfs = callSpectrumPackage ./initramfs {};
  version = import ../lib/version.nix;
  efiArch = stdenv.hostPlatform.efiArch;
  kernel = "${rootfs.kernel}/${stdenv.hostPlatform.linux-kernel.target}";
  systemd = systemdUkify.overrideAttrs ({ mesonFlags ? [], ... }: {
    # The default limit is too low to build a generic aarch64 distro image:
    # https://github.com/systemd/systemd/pull/37417
    mesonFlags = mesonFlags ++ [ "-Defi-stub-extra-sections=3000" ];
  });
in

runCommand "spectrum-verity" {
  nativeBuildInputs = [ cryptsetup systemd bash ];
  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
  dontFixup = true;
  passthru = { inherit systemd; };
} ''
  { \
      printf "[UKI]\nDeviceTreeAuto="
      if [ -d ${rootfs.kernel}/dtbs ]; then
          find ${rootfs.kernel}/dtbs -name '*.dtb' -print0 | tr '\0' ' '
      fi
  } | ukify build \
      --output "$out" \
      --config /dev/stdin \
      --linux ${kernel} \
      --initrd ${initramfs} \
      --os-release $'NAME="Spectrum"\n' \
      --cmdline "ro intel_iommu=on x-spectrum-roothash=$$(< ${verity}/rootfs.verity.roothash) x-spectrum-version=${version}"
  ''
) (_: {})
