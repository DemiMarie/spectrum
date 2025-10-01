#!/bin/sh -e
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2024 Alyssa Ross <hi@alyssa.is>

if [ $# -gt 1 ]; then
	echo "Usage: $0 [<patch version>]"
	exit 1
fi

version="$(nix-instantiate --eval --json -A cloud-hypervisor.version pkgs | jq -r .)"
name="cloud-hypervisor-$version-spectrum${1-0}-patches"

dir="$(mktemp -d)"
trap 'rm -rf -- "$dir"' EXIT

mkdir -p -- "$dir/$name/LICENSES"
cp -- LICENSES/Apache-2.0.txt LICENSES/LicenseRef-BSD-3-Clause-Google.txt \
	"$dir/$name/LICENSES"
cat pkgs/cloud-hypervisor/*.patch >"$dir/$name/cloud-hypervisor.patch"
cat pkgs/cloud-hypervisor/vhost/*.patch >"$dir/$name/vhost.patch"
tar -C "$dir" -czf "$name.tar.gz" -- "$name"
