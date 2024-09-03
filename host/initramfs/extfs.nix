# SPDX-FileCopyrightText: 2021-2022 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: MIT

{ callSpectrumPackage, runCommand, e2fsprogs }:

let
  netvm = callSpectrumPackage ../../vm/sys/net {
    # inherit (foot) terminfo;
  };

  appvm-firefox = callSpectrumPackage ../../vm/app/firefox.nix {};
  appvm-foot = callSpectrumPackage ../../vm/app/foot.nix {};
  appvm-gnome-text-editor = callSpectrumPackage ../../vm/app/gnome-text-editor.nix {};
in

runCommand "ext.ext4" {
  nativeBuildInputs = [ e2fsprogs ];
  __structuredAttrs = true;
  unsafeDiscardReferences = { out = true; };
} ''
  mkdir -p root/svc/data/{appvm-{firefox,foot,gnome-text-editor},netvm}
  cd root

  tar -C ${netvm}/lib/spectrum/vm/netvm -c . | tar -C svc/data/netvm -x
  tar -C ${appvm-firefox} -c . | tar -C svc/data/appvm-firefox -x
  tar -C ${appvm-foot} -c . | tar -C svc/data/appvm-foot -x
  tar -C ${appvm-gnome-text-editor} -c . | tar -C svc/data/appvm-gnome-text-editor -x

  mkfs.ext4 -d . $out 16T
  resize2fs -M $out

  # The generated image will have all files owned by the uid and gid
  # mkfs.ext4 was run as, so we need to normalize ownership to root.
  find -exec echo $'set_inode_field {} uid 0\nset_inode_field {} gid 0' ';' |
      debugfs -wf - $out
''
