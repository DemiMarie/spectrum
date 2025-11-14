# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2023 Alyssa Ross <hi@alyssa.is>

import ../../lib/call-package.nix (
{ callSpectrumPackage, runCommand, e2fsprogs, tar2ext4 }:

runCommand "eosimages.img" {
  nativeBuildInputs = [ e2fsprogs tar2ext4 ];
  imageName = "Spectrum-0.0-x86_64-generic.0.Live.img";
  image = callSpectrumPackage ../live {};
  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
  dontFixup = true;
} ''
  set -o pipefail
  mkdir dir
  cd dir
  ln -s -- "$image" "$imageName"
  sha256sum -- "$imageName" > "$imageName.sha256" &
  pid=$!
  gzip -9 < "$image" > "$imageName.gz"
  sha256sum -- "$imageName.gz" > "$imageName.gz.sha256"
  wait "$pid"
  tar -ch -- "$imageName.gz" "$imageName.gz.sha256" "$imageName.sha256" | tar2ext4 -o "$out"
  e2label "$out" eosimages
'') (_: {})
