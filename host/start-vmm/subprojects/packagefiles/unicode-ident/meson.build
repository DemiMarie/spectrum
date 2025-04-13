# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

project('unicode-ident', 'rust', version : '1.0.9',
  default_options : ['build.rust_std=2018', 'rust_std=2018'],
  meson_version : '>=1.3.0')

unicode_ident = static_library('unicode_ident', 'src/lib.rs',
  native : true,
  rust_abi : 'rust')

unicode_ident_dep = declare_dependency(link_with : unicode_ident)

meson.override_dependency('unicode-ident-rs', unicode_ident_dep, native : true)
