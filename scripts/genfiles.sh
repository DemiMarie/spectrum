#!/usr/bin/env -S LC_ALL=C LANGUAGE=C bash --
set -euo pipefail
unset output_file astatus
case $0 in
(/*) cd "${0%/*}/..";;
(*/*) cd "./${0%/*}/..";;
(*) cd ..;;
esac
for i in host/rootfs img/app vm/sys/net; do
    output_file=$i/file-list.mk
    {
	git -C "$i" -c core.quotePath=true ls-files $'--format=%(objectmode)\t%(path)' -- image |
	sort -t $'\t' -k 2
	echo DONE
    } |
    gawk -v "out_file=$output_file.tmp" -E scripts/genfiles.awk
    if [ -f "$output_file" ]; then
	    # Avoid changing output file if it is up to date, as that
	    # would cause unnecessary rebuilds.
	    if cmp -s -- "$output_file.tmp" "$output_file"; then
		    rm -- "$output_file.tmp"
		    continue
	    else
		    astatus=$?
		    if [ "$astatus" != 1 ]; then exit "$astatus"; fi
	    fi
    fi
    mv -- "$output_file.tmp" "$output_file"
done
