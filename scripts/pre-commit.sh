#!/bin/sh --
set -eu
case $0 in
(/*) cd ${0%/*}/..;;
(*/*) cd ./${0%/*}/..;;
(*) cd ..;;
esac
for i in host/rootfs img/app vm/sys/net; do
	scripts/genfiles.sh "$i"
	git add -- "$i/file-list.mk"
done
