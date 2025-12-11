# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023-2024 Alyssa Ross <hi@alyssa.is>

import ../../../lib/call-package.nix (
{ callSpectrumPackage, rootfs, testers }:

let
  inherit (rootfs) appvm;
  run = callSpectrumPackage ../../../vm/app/foot.nix {};
  surface-notify = callSpectrumPackage ./surface-notify {};
in

testers.nixosTest ({ lib, pkgs, ... }: {
  name = "spectrum-wayland";

  nodes.machine = { ... }: {
    hardware.graphics.enable = true;

    services.udev.extraRules = ''
      KERNEL=="card0", TAG+="systemd"
    '';

    systemd.mounts = [
      {
        name = "shared-config.mount";
        options = "bind";
        what = "${run}/fs";
        where = "/shared/config";
      }
    ];

    systemd.services.cloud-hypervisor = {
      after = [ "crosvm-gpu.service" "weston.service" ];
      requires = [ "crosvm-gpu.service" "weston.service" ];
      serviceConfig.ExecStart = "${lib.getExe pkgs.cloud-hypervisor} --memory shared=on --disk path=${appvm}/lib/spectrum/img/appvm/blk/root.img,readonly=on --cmdline \"console=ttyS0 root=PARTLABEL=root\" --fs socket=/run/virtiofsd.sock,tag=host --gpu socket=/run/crosvm-gpu.sock --vsock cid=3,socket=/run/vsock.sock --serial tty --console null --kernel ${appvm}/lib/spectrum/img/appvm/vmlinux";
    };

    systemd.services.crosvm = {
      after = [ "crosvm-gpu.service" "weston.service" ];
      requires = [ "crosvm-gpu.service" "weston.service" ];
      serviceConfig.ExecStart = "${lib.getExe pkgs.crosvm} run -s /run/crosvm --disk ${appvm}/lib/spectrum/img/appvm/blk/root.img -p \"console=ttyS0 root=PARTLABEL=root\" --vhost-user fs,socket=/run/virtiofsd.sock --vhost-user gpu,socket=/run/crosvm-gpu.sock --vsock cid=3 --serial type=stdout,hardware=virtio-console,stdin=true ${appvm}/lib/spectrum/img/appvm/vmlinux";
      serviceConfig.ExecStop = "${lib.getExe pkgs.crosvm} stop /run/crosvm";
    };

    systemd.services.crosvm-gpu = {
      requires = [ "weston.service" ];
      script = ''
        rm -f /run/crosvm-gpu.sock
        (
            while ! [ -S /run/crosvm-gpu.sock ]; do
                sleep .1
            done
            systemd-notify --ready --no-block
        ) &
        exec ${lib.getExe pkgs.crosvm} device gpu \
            --socket /run/crosvm-gpu.sock \
            --wayland-sock /run/wayland-1 \
            --params '{"context-types":"cross-domain"}'
      '';
      serviceConfig.NotifyAccess = "all";
      serviceConfig.Type = "notify";
    };

    systemd.services.surface-notify-socket = {
      serviceConfig.ExecStart = "${pkgs.coreutils}/bin/mkfifo /run/surface-notify";
      serviceConfig.ExecStop = "${pkgs.coreutils}/bin/rm -f /run/surface-notify";
      serviceConfig.RemainAfterExit = true;
      serviceConfig.Type = "oneshot";
    };

    systemd.services.weston = {
      after = [ "dev-dri-card0.device" "surface-notify-socket.service" ];
      wants = [ "dev-dri-card0.device" "surface-notify-socket.service" ];
      environment.XDG_RUNTIME_DIR = "/run";
      environment.WAYLAND_DEBUG = "server";
      serviceConfig.ExecStart = "${lib.getExe pkgs.westonLite} --modules ${surface-notify}/lib/weston/surface-notify.so,systemd-notify.so";
      serviceConfig.TTYPath = "/dev/tty7";
      serviceConfig.Type = "notify";
    };

    systemd.services.virtiofsd = {
      serviceConfig.ExecStart = "${lib.getExe pkgs.virtiofsd} --fd 3 --shared-dir /shared --tag host";
      serviceConfig.Restart = "on-success";
      requires = [ "shared-config.mount" ];
      after = [ "shared-config.mount" ];
    };

    systemd.sockets.virtiofsd = {
      listenStreams = [ "/run/virtiofsd.sock" ];
      wantedBy = [ "sockets.target" ];
    };

    virtualisation.qemu.options =
      lib.optionals (!pkgs.stdenv.hostPlatform.isx86)
        [ "-machine" "accel=tcg,virtualization=on" ];
  };

  testScript = { ... }: ''
    machine.wait_for_unit('multi-user.target')

    machine.start_job('crosvm.service')
    machine.wait_for_unit('surface-notify-socket.service');
    machine.succeed('test "$(wc -c /run/surface-notify)" = "1 /run/surface-notify"', timeout=360)
    machine.screenshot('crosvm')
    machine.stop_job('crosvm-gpu.service')
    machine.stop_job('crosvm.service')

    machine.systemctl('restart surface-notify-socket')
    machine.wait_for_unit('surface-notify-socket')
    machine.start_job('cloud-hypervisor.service')
    machine.succeed('test "$(wc -c /run/surface-notify)" = "1 /run/surface-notify"', timeout=360)
    machine.screenshot('cloud-hypervisor')
  '';
})) (_: {})
