# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2024 Alyssa Ross <hi@alyssa.is>

project('spectrum-tools', 'c',
  default_options : {
    'c_std': 'c23',
    'rust_std': '2018',
    'warning_level': '3',
  })

add_project_arguments('-Wno-error=attributes', language : 'c')

if get_option('host')
  add_languages('rust')

  if not get_option('unwind')
    add_project_arguments('-C', 'panic=abort', language : 'rust')
  endif

  miniserde_dep = dependency('miniserde-rs')

  subdir('lsvm')
  subdir('start-vmm')
endif

if get_option('guest')
  subdir('xdg-desktop-portal-spectrum')
endif
