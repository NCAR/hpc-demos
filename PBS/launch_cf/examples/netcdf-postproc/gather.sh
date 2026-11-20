#!/bin/bash
#
# The serial phase, after launch_cf has run every step.
#
# The parallel phase reduced each input file to a region; this joins those
# pieces into the finished products.  It is deliberately NOT part of the command
# file: it has to wait for every step, so it runs once, afterwards.  That
# split -- an embarrassingly parallel phase followed by a small gather -- is the
# usual shape of this kind of analysis.
#
# It gathers exactly the outputs of the inputs in ./data, and refuses to run if
# any are missing: a failed step would otherwise leave a silent gap in the time
# series.  Anything else in the output directory, such as an earlier run on a
# different parameter, is left out.
#
# Usage: ./gather.sh [output dir of a run]     (default ./out.unpinned)
#        DATADIR=/other/inputs ./gather.sh ...

set -u
d="${1:-./out.unpinned}"
datadir="${DATADIR:-./data}"
[ -d "${d}" ] || { echo "ERROR: no such directory: ${d}"; exit 1; }

# NCO runs here on the login node; config_env.sh only loads it inside the job
command -v ncrcat >/dev/null || module load nco 2>/dev/null
command -v ncrcat >/dev/null || { echo "ERROR: NCO not loaded -- module load nco"; exit 1; }

inputs=( "${datadir}"/*.nc )
[ -e "${inputs[0]}" ] || { echo "ERROR: no inputs in ${datadir}/ to gather the outputs of"; exit 1; }

# the outputs each input should have produced, in input (time) order
means=() ; maxes=() ; series=() ; missing=0
for f in "${inputs[@]}"; do
    b=$(basename "${f}" .nc)
    for kind in mean max series; do
        if [ ! -s "${d}/${b}.${kind}.nc" ]; then
            [ ${missing} -lt 5 ] && echo "  missing: ${d}/${b}.${kind}.nc"
            missing=$(( missing + 1 ))
        fi
    done
    means+=( "${d}/${b}.mean.nc" )
    maxes+=( "${d}/${b}.max.nc" )
    series+=( "${d}/${b}.series.nc" )
done
if [ ${missing} -gt 0 ]; then
    cat <<MSG
ERROR: ${missing} output(s) missing for the ${#inputs[@]} inputs in ${datadir}/.
Look for steps that failed:  grep -l ERROR stdout-*/step-*.out
MSG
    exit 1
fi

others=$(ls -1 "${d}"/*.nc 2>/dev/null | grep -v '/regional_' | wc -l | tr -d ' ')
others=$(( others - 3 * ${#inputs[@]} ))
[ ${others} -gt 0 ] && echo "note: ignoring ${others} file(s) in ${d}/ not made from the inputs in ${datadir}/"

echo "Gathering ${#inputs[@]} files from ${d}/"

# a continuous regional time series across every input period
ncrcat -O "${series[@]}" "${d}/regional_timeseries.nc" || exit 1

# the mean of each input period, one record per input file
ncrcat -O "${means[@]}" "${d}/regional_period_means.nc" || exit 1

# The climatology: the mean over every record of the time series.  Averaging the
# per-file means instead would weight every file alike, but half-month files
# hold anywhere from 26 to 32 forecasts.  Forecast products then need the same
# average over forecast_hour that process_file.sh gave the per-file means.
clim="${d}/regional_climatology.nc"
ncra -O "${d}/regional_timeseries.nc" "${clim}" || exit 1
inner_time_dim="${INNER_TIME_DIM:-forecast_hour}"
if ncks --cdl -m "${clim}" 2>/dev/null | grep -Eq "^[[:space:]]+${inner_time_dim} = "; then
    ncwa -O -a "${inner_time_dim}" "${clim}" "${clim}" || exit 1
else
    inner_time_dim=""
fi
# and, as process_file.sh does for the per-file means, drop what averaging
# turns into nonsense: the "mean" yyyymmddhh date and the "mean" forecast hour
drop=""
hdr=$(ncks --cdl -m "${clim}" 2>/dev/null)
for v in utc_date ${inner_time_dim}; do
    echo "${hdr}" | grep -Eq "^[[:space:]]+[a-z0-9 ]+ ${v}( ;|\()" && drop="${drop:+${drop},}${v}"
done
[ -z "${drop}" ] || ncks -O -x -v "${drop}" "${clim}" "${clim}" || exit 1

# and the extreme of the per-file extremes, which needs no weighting
ncra -O -y max "${maxes[@]}" "${d}/regional_maximum.nc" || exit 1

echo
ls -lh "${d}"/regional_*.nc | awk '{print "  "$9"  "$5}'
echo
echo "Inspect with:  ncdump -h ${d}/regional_climatology.nc"
