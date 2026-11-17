#!/bin/bash
#
# List ERA5 temperature files (one per day) for the study, in date order.
# Each run of submit_study.sh takes its own consecutive slice of this list,
# so no run reads a file an earlier run may have left in a cache.
#
#   ./make_filelist.sh                 2020-01 .. 2023-12  ->  era5_t_files.txt
#   FIRST=201901 LAST=201912 ./make_filelist.sh

set -euo pipefail
ROOT=/glade/campaign/collections/gdex/data/d633000/e5.oper.an.pl
FIRST="${FIRST:-202001}"
LAST="${LAST:-202312}"

for dir in "${ROOT}"/[0-9][0-9][0-9][0-9][0-9][0-9]; do
    m=$(basename "${dir}")
    [ "${m}" -lt "${FIRST}" ] || [ "${m}" -gt "${LAST}" ] && continue
    ls "${dir}"/e5.oper.an.pl.128_130_t.ll025sc.*.nc
done > era5_t_files.txt
echo "$(wc -l < era5_t_files.txt) files in era5_t_files.txt"
