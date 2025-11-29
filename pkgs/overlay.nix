# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

(final: super: {
  cloud-hypervisor = import ./cloud-hypervisor { inherit final super; };

  flatpak = super.flatpak.override (
    final.lib.optionalAttrs final.stdenv.hostPlatform.isMusl {
      withMalcontent = false;
    }
  );

  mailutils = super.mailutils.overrideAttrs (_: (
    final.lib.optionalAttrs final.stdenv.hostPlatform.isMusl { doCheck = false; }
  ));

  skawarePackages = import ./skaware-packages { inherit final super; };
})
