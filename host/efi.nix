# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>

import ../lib/call-package.nix (
{ bash, callSpectrumPackage, cryptsetup, runCommand
, stdenv, systemdUkify, rootfs
}:
let
  initramfs = callSpectrumPackage ./initramfs {};
  kernel = "${rootfs.kernel}/${stdenv.hostPlatform.linux-kernel.target}";
  systemd = systemdUkify.overrideAttrs ({ mesonFlags ? [], ... }: {
    # The default limit is too low to build a generic aarch64 distro image:
    # https://github.com/systemd/systemd/pull/37417
    mesonFlags = mesonFlags ++ [ "-Defi-stub-extra-sections=3000" ];
  });
in

runCommand "spectrum-efi" {
  nativeBuildInputs = [ cryptsetup systemd bash ];
  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
  dontFixup = true;
  passthru = { inherit systemd; };
  env = {
    DTBS = "${rootfs.kernel}/dtbs";
    KERNEL = kernel;
    INITRAMFS = initramfs;
    ROOTFS = rootfs;
  };
} ''
  read -r roothash < "$ROOTFS/rootfs.verity.roothash"
  { \
      printf "[UKI]\nDeviceTreeAuto="
      if [ -d "$DTBS" ]; then
          find "$DTBS" -name '*.dtb' -print0 | tr '\0' ' '
      fi
  } | ukify build \
      --output "$out" \
      --config /dev/stdin \
      --linux "$KERNEL" \
      --initrd "$INITRAMFS" \
      --os-release $'NAME="Spectrum"\n' \
      --cmdline "ro intel_iommu=on roothash=$roothash"
  ''
) (_: {})
