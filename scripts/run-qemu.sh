#!/bin/sh -ue
# SPDX-FileCopyrightText: 2023-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-License-Identifier: EUPL-1.2+

# This script wraps around QEMU to paper over platform differences,
# which can't be handled portably in Make language.

accel=kvm

case "${ARCH:="$(uname -m)"}" in
	aarch64)
		machine=virt,gic-version=3,iommu=smmuv3
		;;
	x86_64)
		append="console=ttyS0${append:+ $append}"
		iommu=intel-iommu,intremap=on
		machine=q35,kernel-irqchip=split
		;;
esac

i=0
while [ $i -lt $# ]; do
	arg="$1"
	shift

	case "$arg" in
		-append)
			set -- "$@" -append "${append:+$append }$1"
			i=$((i + 2))
			shift
			continue
			;;
		-device)
			IFS=,
			for opt in $1; do
				case "$opt" in
					*-iommu)
						unset iommu
						;;
				esac
				break
			done
			unset IFS
			;;
		-machine)
			set -- "$@" "$arg"
			i=$((i + 1))
			arg=

			IFS=,
			for opt in $1; do
				case "$opt" in
					virtualization=on)
						case "$ARCH" in
							aarch64)
								accel=tcg
								;;
							*)
								continue
								;;
						esac
						;;
				esac

				arg="$arg${arg:+,}$opt"
			done
			unset IFS

			shift
	esac

	set -- "$@" "$arg"

	i=$((i + 1))
done

for arg; do
	case "$arg" in
		-append)
			append=
			;;
		-kernel)
			kernel=1
			;;
	esac
done

set -x
exec ${QEMU_SYSTEM:-qemu-system-$ARCH} \
	-accel "$accel" \
	-machine "$machine" \
	${kernel:+${append:+-append "$append"}} \
	${iommu:+-device "$iommu"} \
	"$@"
