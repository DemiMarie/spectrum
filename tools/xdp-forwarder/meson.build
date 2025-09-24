# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2025 Yureka Lilian <yureka@cyberchaos.dev>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
# SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>

libbpf = dependency('libbpf', version : '>= 1.6.2')

executable('set-router-iface', 'set_router_iface.c',
  dependencies : libbpf,
  install : true)

clang = find_program('clang', native : true)

bpf_o_cmd = [
  clang.full_path(),
  '-fno-stack-protector',
  '-fno-strict-aliasing',
  '-fwrapv', '-fwrapv-pointer',
  '-Wall',
  '-Wextra',
  '-Wno-compare-distinct-pointer-types',
  '-Wno-sign-compare',
  '-O2',
  '-target', 'bpf',
  '-I', meson.current_source_dir() + '/include',
  '-g',
  '-c',
  '-o', '@OUTPUT@',
  '-MD',
  '-MQ', '@OUTPUT',
  '-MF', '@DEPFILE@',
  '--',
  '@INPUT@',
]

prog_router_o = custom_target(
  input : 'prog_router.c',
  output : 'prog_router.o',
  depfile : 'prog_router.o.dep',
  command : bpf_o_cmd,
  install: true,
  install_dir: 'lib/xdp')

prog_physical_o = custom_target(
  input : 'prog_physical.c',
  output : 'prog_physical.o',
  depfile : 'prog_physical.o.dep',
  command : bpf_o_cmd,
  install: true,
  install_dir: 'lib/xdp')
