# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2024-2025 Alyssa Ross <hi@alyssa.is>

project('spectrum-tools', 'c',
  default_options : {
    'c_std': 'c23',
    'rust_std': '2018',
    'warning_level': '3',
  })

add_project_arguments('-Wno-error=attributes', language : 'c')
add_project_arguments('-Werror=missing-prototypes', language : 'c')
add_project_arguments('-Werror=missing-declarations', language : 'c')

if not get_option('unwind')
  add_project_arguments('-C', 'panic=abort', language : 'rust')
endif

if get_option('build')
  executable('lseek', 'lseek.c', c_args : '-D_XOPEN_SOURCE', install : true)
endif

if get_option('host')
  add_languages('rust')

  miniserde_dep = dependency('miniserde-rs')

  executable('sd-notify-adapter', 'sd-notify-adapter.c',
    c_args : '-D_GNU_SOURCE',
    install: true)

  executable('updates-dir-check', 'updates-dir-check.c',
    c_args : '-D_GNU_SOURCE',
    install: true)

  subdir('lsvm')
  subdir('start-vmm')
endif

if get_option('app')
  subdir('xdg-desktop-portal-spectrum')
endif

if get_option('driver')
  subdir('xdp-forwarder')
endif
