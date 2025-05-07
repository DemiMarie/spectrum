# SPDX-FileCopyrightText: 2023 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

project('syn', 'rust', version : '2.0.58',
  default_options : ['build.rust_std=2021', 'rust_std=2021'],
  meson_version : '>=1.3.0')

proc_macro2_dep = dependency('proc-macro2-rs', native : true)
quote_dep = dependency('quote-rs', native : true)

syn = static_library('syn', 'src/lib.rs',
  dependencies : [proc_macro2_dep, quote_dep],
  native : true,
  rust_args : [
    '--cfg', 'feature="clone-impls"',
    '--cfg', 'feature="derive"',
    '--cfg', 'feature="parsing"',
    '--cfg', 'feature="printing"',
    '--cfg', 'feature="proc-macro"',
  ],
  rust_abi : 'rust')

syn_dep = declare_dependency(
  dependencies : [proc_macro2_dep, quote_dep],
  link_with : syn)

meson.override_dependency('syn-rs', syn_dep, native : true)
