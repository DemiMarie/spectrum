# SPDX-FileCopyrightText: 2023-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

project('itoa', 'rust', version : '1.0.10', default_options : ['rust_std=2018'])

if not get_option('unwind')
  add_project_arguments('-C', 'panic=abort', language : 'rust')
endif

itoa = static_library('itoa', 'src/lib.rs', rust_abi : 'rust')

itoa_dep = declare_dependency(link_with : itoa)

meson.override_dependency('itoa-rs', itoa_dep)
