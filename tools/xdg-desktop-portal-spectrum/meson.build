# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2024 Alyssa Ross <hi@alyssa.is>

dbus = dependency('dbus-1')

install_data('spectrum.portal',
  install_dir : get_option('datadir') / 'xdg-desktop-portal/portals')

service_conf_data = configuration_data()
service_conf_data.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input : 'org.freedesktop.impl.portal.desktop.spectrum.service.in',
  output : 'org.freedesktop.impl.portal.desktop.spectrum.service',
  configuration : service_conf_data,
  install_dir : get_option('datadir') / 'dbus-1/services')

exe_conf_data = configuration_data()
exe_conf_data.set_quoted('HOST_FS_ROOT_DIR', get_option('hostfsrootdir'))
configure_file(
  output : 'config.h',
  configuration : exe_conf_data)

executable('xdg-desktop-portal-spectrum', 'xdg-desktop-portal-spectrum.c',
  dependencies : dbus,
  install : true)
