# SPDX-FileCopyrightText: 2023-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

project('ryu', 'rust',
  version : '1.0.17',
  default_options : ['rust_std=2018'],
  meson_version : '>=1.3.0')

if not get_option('unwind')
  add_project_arguments('-C', 'panic=abort', language : 'rust')
endif

ryu = static_library('ryu', 'src/lib.rs', rust_abi : 'rust')

ryu_dep = declare_dependency(link_with : ryu)

meson.override_dependency('ryu-rs', ryu_dep)
