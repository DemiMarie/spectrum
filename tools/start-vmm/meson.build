# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2022-2024 Alyssa Ross <hi@alyssa.is>

rust_lib = static_library('start_vmm', 'lib.rs',
  dependencies : miniserde_dep)

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
    rust_args : ['--test'])
  test('Rust unit tests', test_exe, protocol : 'rust')

  subdir('tests')
endif
