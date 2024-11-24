# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2022-2023 Alyssa Ross <hi@alyssa.is>

rust_helper = static_library('test_helper', 'helper.rs',
  dependencies : rust_lib_dep)

test('tap_open', executable('tap_open', 'tap_open.c', '../net-util.c',
  c_args : '-D_GNU_SOURCE'))
test('tap_open (name too long)', executable('tap_open-name-too-long',
  'tap_open-name-too-long.c', '../net-util.c', c_args : '-D_GNU_SOURCE'))

test('vm_command-basic', executable('vm_command-basic',
  'vm_command-basic.rs',
  dependencies : rust_lib_dep,
  link_with : rust_helper))
test('vm_command-multiple-disks', executable('vm_command-multiple-disks',
  'vm_command-multiple-disks.rs',
  dependencies : rust_lib_dep,
  link_with : rust_helper))
