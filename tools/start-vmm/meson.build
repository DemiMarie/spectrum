# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2022-2024 Alyssa Ross <hi@alyssa.is>

project('start-vmm', 'rust', 'c',
  default_options : {
    'c_std': 'c23',
    'rust_std': '2018',
    'warning_level': '3',
  })

add_project_arguments('-D_GNU_SOURCE', '-Wno-error=attributes', language : 'c')

if not get_option('unwind')
  add_project_arguments('-C', 'panic=abort', language : 'rust')
endif

miniserde_dep = dependency('miniserde-rs')

c_lib = static_library('start-vmm', 'fork.c', 'net.c', 'net-util.c', 'unix.c')
rust_lib = static_library('start_vmm', 'lib.rs',
  dependencies : miniserde_dep,
  link_with : c_lib)

rust_lib_dep = declare_dependency(
  dependencies : miniserde_dep,
  link_with : rust_lib)

executable('start-vmm', 'start-vmm.rs',
  dependencies : miniserde_dep,
  link_with : rust_lib,
  install : true)

if get_option('tests')
  test_exe = executable('start-vmm-test', 'lib.rs',
    dependencies : miniserde_dep,
    rust_args : ['--test'],
    link_with : c_lib)
  test('Rust unit tests', test_exe, protocol : 'rust')

  subdir('tests')
endif
