# SPDX-FileCopyrightText: 2023-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

project('miniserde', 'rust', version : '0.1.41',
  default_options : ['build.rust_std=2021', 'rust_std=2021', 'warning_level=0'],
  meson_version : '>=1.3.0')

rust = import('rust')

quote_dep = dependency('quote-rs', native : true)
syn_dep = dependency('syn-rs', native : true)

mini_internal = rust.proc_macro('mini_internal', 'derive/src/lib.rs',
  dependencies : [quote_dep, syn_dep])

itoa_dep = dependency('itoa-rs')
ryu_dep = dependency('ryu-rs')

miniserde_rust_args = []
if not get_option('unwind')
  miniserde_rust_args += ['-C', 'panic=abort']
endif

miniserde = static_library('miniserde', 'src/lib.rs',
  dependencies : [itoa_dep, ryu_dep],
  link_with : mini_internal,
  rust_args : miniserde_rust_args,
  rust_abi : 'rust')

miniserde_dep = declare_dependency(
  dependencies : [itoa_dep, ryu_dep],
  link_with : miniserde)

meson.override_dependency('miniserde-rs', miniserde_dep)
