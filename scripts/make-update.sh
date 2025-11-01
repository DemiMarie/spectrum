#!/usr/bin/env bash
set -eu
case $0 in
(/*) dir=${0%/*};;
(*/*) dir=./${0%/*};;
(*) dir=.;;
esac
if [ "$#" != 2 ]; then
	echo "Usage: $0 target-directory signing-key-fingerprint" >&2
	exit 1
fi
if ! [[ "$2" =~ ^[0-9A-F]{40}$ ]]; then
	printf 'Bad signing key fingerprint %q\n' "$1" >&2
	exit 1
fi
read -r version < "$dir/../version"
mkdir -p -- "$1"
store_path=$(nix-build --no-out-link "$dir/../release/update.nix")
cp -t "$1" -- "$store_path"/{"Spectrum_$version".{efi,root,verity},SHA256SUMS}
gpg2 --sign -u "$2" --armor < "$1/SHA256SUMS" > "$1/SHA256SUMS.gpg"
