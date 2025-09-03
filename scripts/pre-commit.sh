#!/bin/sh --
set -eu
case $0 in
(/*) cd ${0%/*}/..;;
(*/*) cd ./${0%/*}/..;;
(*) cd ..;;
esac
scripts/genfiles.sh
git add -- "$i/file-list.mk"
