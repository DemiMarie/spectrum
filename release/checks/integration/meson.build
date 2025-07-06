# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

project('spectrum-integration-tests', 'c',
  default_options : { 'c_std': 'c23' },
  meson_version : '>=1.6.0')

add_project_arguments('-D_GNU_SOURCE', language : 'c')

run_qemu = find_program('../../../scripts/run-qemu.sh')

lib = static_library('spectrum-integration-test', 'lib.c')

foreach test : ['appimage', 'late-serial', 'networking']
  test(test, executable(test, test + '.c', link_with : lib),
    timeout : 300,
    args : [
      run_qemu,
      get_option('efi'),
      get_option('img'),
      get_option('user_data'),
    ])
endforeach
