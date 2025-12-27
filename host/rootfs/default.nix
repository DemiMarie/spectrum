# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021-2025 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie

import ../../lib/call-package.nix (
{ callSpectrumPackage, config, spectrum-build-tools
, src, pkgsMusl, inkscape, linux_latest, xorg
}:
pkgsMusl.callPackage (

{ spectrum-host-tools, spectrum-router
, lib, stdenvNoCC, nixos, runCommand, writeClosure, erofs-utils, s6-rc
, btrfs-progs, bubblewrap, busybox, cloud-hypervisor, cosmic-files
, crosvm, cryptsetup, dejavu_fonts, dbus, execline, foot, fuse3
, iproute2, inotify-tools, jq, kmod, lvm2, mdevd, mesa, mount-flatpak
, s6, s6-linux-init, shadow, socat, systemd, util-linuxMinimal, virtiofsd
, westonLite, xdg-desktop-portal, xdg-desktop-portal-gtk
, xdg-desktop-portal-spectrum-host
}:

let
  inherit (nixosAllHardware.config.hardware) firmware;
  inherit (lib)
    concatMapStringsSep concatStrings escapeShellArgs fileset mapAttrsToList
    mkForce trivial;
  inherit (lib.strings) hasPrefix;

  packages = [
    btrfs-progs bubblewrap cloud-hypervisor cosmic-files crosvm cryptsetup dbus
    execline fuse3 inotify-tools iproute2 jq kmod mdevd mount-flatpak s6
    s6-linux-init s6-rc shadow socat spectrum-host-tools spectrum-router
    virtiofsd xdg-desktop-portal-spectrum-host

    (foot.override { allowPgo = false; })

    (busybox.override {
      # Use a separate file as it is a bit too big.
      extraConfig = builtins.readFile ./busybox-config;
    })

    (util-linuxMinimal.overrideAttrs ({ configureFlags ? [], ... }: {
      # Conflicts with shadow.
      configureFlags = configureFlags ++ [ "--disable-nologin" ];
    }))
  ];

  nixosAllHardware = nixos ({ modulesPath, ... }: {
    imports = [ (modulesPath + "/profiles/all-hardware.nix") ];

    system.stateVersion = trivial.release;
  });

  badConfig = old_config: let (
    hasPrefix "NF" name ||
    hasPrefix "BT_" name ||
    hasPrefix "EXT2_" name ||
    hasPrefix "IP" name ||
    hasPrefix "INET" name ||
    hasPrefix "L2TP" name ||
    hasPrefix "NET" name ||
    hasPrefix "NFS" name ||
    hasPrefix "CEPH" name ||
    hasPrefix "CIFS" name ||
    name == "AX25" ||
    name == "SWIOTLB_XEN") then mkForce unset else value;

  filtered_config =
    let config = linux_latest.configfile.structuredConfig; in
    lib.filterAttrs config (builtins.filter unwantedAttrs (builtins.attrNames config));

  kernel = linux_latest.override {
    structuredConfig = filtered_config;
    moduleStructuredConfig = filtered_config;
    structuredExtraConfig = with lib.kernel; {
      SCSI_PROC_FS = no;

      # No network drivers!
      NETDEVICES = lib.mkForce no;

      # No IP networking!
      INET = lib.mkForce no;

      # No kTLS
      TLS = lib.mkForce no;

      # No Bluetooth
      BT = lib.mkForce no;

      # No NFC
      NFC = no;

      # No wireless on the host, please.
      WIRELESS = lib.mkForce no;
      WLAN = lib.mkForce no;

      # No spanning tree.
      MRP = no;
      VLAN_8021Q = no;

      # No 9pfs
      NET_9P = lib.mkForce no;

      # No AppleTalk
      ATALK = no;

      # No unused filesystems
      XFS_FS = mkForce no;
      EXT2_FS = mkForce no;
      EXT4_FS = mkForce no;
      NTFS_FS = mkForce no;
      NTFS3_FS = mkForce no;
      OCFS2_FS = mkForce no;
      JFS_FS = mkForce no;

      # No ATM
      ATM = mkForce no;

      # No mesh networking
      BATMAN_ADV = mkForce no;

      # No bridging
      BRIDGE = lib.mkForce no;

      # No CAIF, whatever the heck that is.
      CAIF = mkForce no;

      # The Spectrum host will not have a CAN bus!
      CAN = mkForce no;

      # No network filesystems
      NETWORK_FILESYSTEMS = no;

      # No Data Center Bridging
      DCB = mkForce no;

      # No DNS resolution
      DNS_RESOLVER = mkForce no;

      # No hardware switch support
      NET_DSA = mkForce no;

      # No Ethernet redundancy
      HSR = mkForce no;

      # No 802.15.4
      IEEE802154 = mkForce no;

      # No packet sockets
      PACKET = mkForce no;

      # No 802.2 Logical Link Control
      LLC = mkForce no;

      # No ForCES
      NET_IFE = mkForce no;

      # No X.25 LAPB
      LAPB = mkForce no;

      # No 802.11 protocol layer
      MAC80211 = lib.mkForce no;

      # No LoWPAN
      MAC802154 = mkForce no;

      # No Management Component Transport Protocol
      MCTP = no; # TODO: could someone run Spectrum in a server with a BMC?

      # No Multiprotocol Label Switching
      MPLS = mkForce no;

      # No firewalling!
      NETFILTER = lib.mkForce no;

      # No network MAC labeling
      NETLABEL = mkForce no;

      # No netlink diagnostics
      NETLINK_DIAG = mkForce no;

      # No network service headers
      NET_NSH = mkForce no;

      # No OpenVSwitch
      OPENVSWITCH = mkForce no;

      # No support for Nokia cellular modems
      PHONET = mkForce no;

      # No Traffic Control sampling
      PSAMPLE = mkForce no;

      # No Qualcomm IPC Router
      QRTR = mkForce no;

      # No network scheduler
      NET_SCHED = mkForce no;

      # No AF_VSOCK.  The user-mode implementation is used on the host.
      VSOCKETS = mkForce no;

      # No amateur radio.
      HAMRADIO = mkForce no;
      AX25 = mkForce unset;

      # No X.25 protocol
      X25 = mkForce no;

      # No AF_XDP as there are no network devices for it to run on.
      XDP_SOCKETS = mkForce no;
      XDP_SOCKETS_DIAG = mkForce unset;

      # No trivial DMA attacks
      FIREWIRE = mkForce no;
      HOTPLUG_PCI_ACPI = mkForce no;
      HOTPLUG_PCI_PCIE = mkForce no;

      # No 32-bit code
      IA32_EMULATION = mkForce no;
      X86_X32_ABI = mkForce no;

      # No NVMe target support
      NVME_TARGET = mkForce no;

      # No NVMe-oF support
      NVME_HOST_AUTH = mkForce no;
      NVME_FC = mkForce no;

      # No Fibre Channel
      NET_FC = mkForce no;

      # We are a desktop OS.  Enable preemption.
      PREEMPT = mkForce yes;
      PREEMPT_VOLUNTARY = mkForce no;

      # Allow it to be overridden on command line.
      PREEMPT_DYNAMIC = yes;

      # No ROCm userspace on host.  Any host GPU compute would use OpenGL(-ES) or Vulkan.
      HSA_AMD = mkForce no;

      # No Ethernet drivers
      ETHERNET = mkForce no;

      # No old code
      X86_VSYSCALL_EMULATION = mkForce no;

      # No segmented or 32-bit code
      MODIFY_LDT_SYSCALL = mkForce no;

      # We don't use UEFI secure boot in guests.
      KVM_SMM = mkForce no;

      # No POSIX message queues
      POSIX_MQUEUE = mkForce no;

      # No OOB messages on AF_UNIX.  These are only really useful for exploits.
      AF_UNIX_OOB = mkForce no;

      # No machine learning accelerators.  Spectrum's host has no userspace for them.
      DRM_ACCEL = mkForce no;

      # Spectrum can't run under Xen (because it needs virtualization).
      XEN = mkForce no;
      XEN_BALLOON = mkForce unset;
      XEN_BALLOON_MEMORY_HOTPLUG = mkForce unset;
      XEN_DOM0 = mkForce unset;
      XEN_EFI = mkForce unset;
      XEN_HAVE_PVMMU = mkForce unset;
      XEN_PVH = mkForce unset;
      XEN_PVHVM = mkForce unset;
      XEN_SAVE_RESTORE = mkForce unset;
      XEN_SYS_HYPERVISOR = mkForce unset;

      # Unused options from NixOS
      BONDING = mkForce unset;
      BPF_STREAM_PARSER = mkForce unset;
      BRIDGE_VLAN_FILTERING = mkForce unset;
      CLS_U32_MARK = mkForce unset;
      CLS_U32_PERF = mkForce unset;

      # Spectrum does not need to support Xen guests.
      KVM_XEN = mkForce no;

      # No old-style i915 GVT-g
      DRM_I915_GVT = mkForce no;
      DRM_I915_GVT_KVMGT = mkForce no;

      # No RDMA cgroup
      CGROUP_RDMA = mkForce no;

      # No Windows guests (yet)
      KVM_HYPERV = mkForce no;

      # Various hardening options.
      # Crash the kernel if something goes really wrong
      PANIC_ON_OOPS = yes;
      BUG_ON_DATA_CORRUPTION = yes;
      DEBUG_LIST = yes;
      FORTIFY_SOURCE = yes;
      HARDENED_USERCOPY = yes;
      HARDENED_USERCOPY_DEFAULT_ON = yes;
      HARDENED_LIST_HARDENED = yes;
      BUG = yes;
      INIT_ON_FREE_DEFAULT_ON = yes;
      INIT_ON_ALLOC_DEFAULT_ON = yes;
      INIT_STACK_ALL_ZERO = yes;
      ZERO_CALL_USED_REGS = yes;

      # Not used.  Yet.
      SECURITY_APPARMOR = mkForce no;
      # Enable VM checks
      DEBUG_VM = yes;

      # Allow dumping more data to the screen on panics, so that reports from end-users
      # are better.  The default is meant for developer convenience.
      #DRM_PANIC_SCREEN = lib.mkForce (freeform "qr_code");
      DRM_PANIC_SCREEN_QR_CODE = yes;

      # No use for USB gadgets
      USB_GADGET = mkForce no;
   };
  };
  appvm = callSpectrumPackage ../../img/app { inherit (foot) terminfo; };
  netvm = callSpectrumPackage ../../vm/sys/net { inherit (foot) terminfo; };

  # Packages that should be fully linked into /usr,
  # (not just their bin/* files).
  #
  # kmod.lib is dlopen()ed by systemd-udevd via libsystemd-shared.so.
  # It doesn't get picked up from libsystemd-shared.so's RUNPATH due to
  # https://inbox.vuxu.org/musl/20251017-dlopen-use-rpath-of-caller-dso-v1-1-46c69eda1473@iscas.ac.cn/
  usrPackages = [
    appvm dejavu_fonts firmware kernel.modules kmod.lib lvm2 mesa
    netvm systemd westonLite
  ];

  appvms = {
    appvm-firefox = callSpectrumPackage ../../vm/app/firefox.nix {};
    appvm-foot = callSpectrumPackage ../../vm/app/foot.nix {};
    appvm-gnome-text-editor = callSpectrumPackage ../../vm/app/gnome-text-editor.nix {};
    appvm-systemd-sysupdate = callSpectrumPackage ../../vm/app/systemd-sysupdate {};
  };

  packagesSysroot = runCommand "packages-sysroot" {
    depsBuildBuild = [ inkscape ];
    nativeBuildInputs = [ xorg.lndir ];
    src = builtins.path { name = "os-release"; path = ./os-release.in; };
  } ''
    mkdir -p $out/usr/bin $out/usr/share/dbus-1/services \
      $out/usr/share/icons/hicolor/20x20/apps

    # lndir silently ignores existing links, so run it before ln
    # so that ln catches any duplicates.
    for pkg in ${escapeShellArgs usrPackages}; do
        lndir -ignorelinks -silent "$pkg" "$out/usr"
    done

    # Weston doesn't support SVG icons.
    inkscape -w 20 -h 20 \
        -o $out/usr/share/icons/hicolor/20x20/apps/com.system76.CosmicFiles.png \
        ${cosmic-files}/share/icons/hicolor/24x24/apps/com.system76.CosmicFiles.svg

    ln -st $out/usr/bin \
        ${concatMapStringsSep " " (p: "${p}/bin/*") packages} \
        ${xdg-desktop-portal}/libexec/xdg-document-portal \
        ${xdg-desktop-portal-gtk}/libexec/xdg-desktop-portal-gtk
    ln -st $out/usr/share/dbus-1 \
        ${dbus}/share/dbus-1/session.conf
    ln -st $out/usr/share/dbus-1/services \
        ${xdg-desktop-portal-gtk}/share/dbus-1/services/org.freedesktop.impl.portal.desktop.gtk.service

    ${concatStrings (mapAttrsToList (name: path: ''
      ln -s ${path} $out/usr/lib/spectrum/vm/${name}
    '') appvms)}
  '';
in

stdenvNoCC.mkDerivation {
  name = "spectrum-rootfs";

  src = fileset.toSource {
    root = ../..;
    fileset = fileset.intersection src (fileset.unions [
      ./.
      ../../lib/common.mk
      ../../scripts/make-erofs.sh
    ]);
  };
  sourceRoot = "source/host/rootfs";

  nativeBuildInputs = [ cryptsetup erofs-utils spectrum-build-tools s6-rc ];

  env = {
    PACKAGES = runCommand "packages" {} ''
      printf "%s\n/\n" ${packagesSysroot} >$out
      sed p ${writeClosure [ packagesSysroot] } >>$out
    '';
    UPDATE_SIGNING_KEY = builtins.path {
      name = "signing-key";
      path = config.updateSigningKey;
    };
    UPDATE_URL = config.updateUrl;
    VERSION = config.version;
  };

  # The Makefile uses $(ROOT_FS), not $(dest), so it can share code
  # with other Makefiles that also use this variable.
  makeFlags = [ "ROOT_FS=$(out)" ];

  dontInstall = true;

  enableParallelBuilding = true;

  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
  dontFixup = true;

  passthru = {
    inherit appvm firmware kernel nixosAllHardware packagesSysroot;
  };

  meta = with lib; {
    license = licenses.eupl12;
    platforms = platforms.linux;
  };
}
) {}) (_: {})
