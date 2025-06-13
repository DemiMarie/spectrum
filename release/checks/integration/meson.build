# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

project('spectrum-integration-tests', 'c',
  default_options : { 'c_std': 'c23' },
  meson_version : '>=1.6.0')

add_project_arguments('-D_GNU_SOURCE', language : 'c')

test('networking', executable('networking', 'networking.c'),
  timeout : 240,
  args : [
    find_program('../../../scripts/run-qemu.sh'),
    get_option('efi'),
    get_option('img'),
    get_option('user_data'),
  ])
