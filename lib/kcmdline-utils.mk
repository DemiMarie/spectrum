# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2024 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2025 Demi Marie Obenour <demiobenour@gmail.com>
READ_ROOTHASH =  { set -euo pipefail; \
	read -r roothash < build/rootfs.verity.roothash; \
	LC_ALL=C expr "x$$roothash" : '^x[a-f0-9]\{64\}$$' >/dev/null; }

LIVE_IMAGE_DEPS = ../../scripts/format-uuid.awk ../../scripts/make-gpt.sh ../../scripts/make-gpt.bash ../../scripts/sfdisk-field.awk build/rootfs.verity.superblock build/rootfs.verity.roothash ../../scripts/make-live-image.sh ../../lib/kcmdline-utils.mk
