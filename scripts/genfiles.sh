#!/usr/bin/env -S LC_ALL=C LANGUAGE=C bash --
set -euo pipefail
script_file=genfiles.awk
case $0 in
(/*) script_file=${0%/*}/$script_file;;
(*/*) script_file=./${0%/*}/$script_file;;
(*) script_file=./$script_file;;
esac
case ${1-.} in
('') echo 'Directory name cannot be empty' >&2; exit 1;;
(*/) output_file=${1}file-list.mk;;
(*) output_file=${1-.}/file-list.mk;;
esac
{
    git ${1+-C} ${1+"$1"} -c core.quotePath=true ls-files $'--format=%(objectmode)\t%(path)' -- image |
    sort -t $'\t' -k 2
    echo DONE
} |
gawk -v "out_file=$output_file.tmp" -E "$script_file"
status=0
cmp -s -- "$output_file.tmp" "$output_file" || status=$?
case $status in
(0) rm -- "$output_file.tmp";;
(1) mv -- "$output_file.tmp" "$output_file";;
(*) exit "$?";;
esac
