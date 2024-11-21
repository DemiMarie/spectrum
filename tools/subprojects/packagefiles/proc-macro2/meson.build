# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

project('proc-macro2', 'rust', version : '1.0.93',
  default_options : ['build.rust_std=2021', 'rust_std=2021', 'warning_level=0'],
  meson_version : '>=1.3.0')

unicode_ident_dep = dependency('unicode-ident-rs', native : true)

proc_macro2 = static_library('proc_macro2', 'src/lib.rs',
  dependencies : unicode_ident_dep,
  native : true,
  rust_args : ['--cfg', 'feature="proc-macro"'],
  rust_abi : 'rust')

proc_macro2_dep = declare_dependency(
  dependencies : unicode_ident_dep,
  link_with : proc_macro2)

meson.override_dependency('proc-macro2-rs', proc_macro2_dep, native : true)
