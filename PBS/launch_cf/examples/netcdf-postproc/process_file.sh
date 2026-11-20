#!/bin/bash
#
# ONE STEP of the command file: reduce one ERA5 file to three regional
# diagnostics, computing all three at the same time.
#
#   ncra           regional time MEAN     -> the mean over this file's period
#   ncra -y max    regional time MAXIMUM  -> the companion extremes field
#   ncks           regional TIME SERIES   -> full time resolution, region only
#
# Each reads the same input, applies the same lat/lon hyperslab, and makes a
# different reduction, so they are independent and run concurrently.  ncra
# streams the file a record at a time; ncks holds the whole region of a
# variable, so its memory grows with the region (a few hundred MB for the
# default, over a GB for the globe).  gen_cmdfile_postproc.sh measures both.
#
# Once every step has run, ./gather.sh joins the pieces into the finished
# products: a continuous regional time series and a climatology over all files.
#
# The point for launch_cf is the "&": a step is THREE processes, not one.  A
# node therefore holds cores/3 steps, which is what --nthreads 3 tells it.
# Placement then matters:
#
#   * pinned  (taskset -c a-b)  a step's three processes stay on its own three
#                               cores whether they are busy or blocked on I/O
#   * unpinned                  the scheduler can use cores that other steps
#                               have left idle while they wait on their own I/O
#
# The step exits non-zero if any of its operations fails, and only finished
# outputs are given their final names, so gather.sh never sees a partial file.
#
# Usage: process_file.sh <input.nc> [output dir] [lat range] [lon range]
#   e.g. process_file.sh in.nc ./out -90.,90. 0.,359.75     (the whole globe)

set -u

usage="usage: process_file.sh <input.nc> [output dir] [lat range] [lon range]"
infile="${1:?${usage}}"
outdir="${2:-./out}"

# The region to study.  ERA5 longitudes run 0-360, latitudes 90 to -90.
# The default is roughly the contiguous United States; gen_cmdfile_postproc.sh
# writes the region it measured into every step.
lat_range="${3:-${LAT_RANGE:-25.,50.}}"
lon_range="${4:-${LON_RANGE:-235.,295.}}"

[ -r "${infile}" ] || { echo "ERROR: cannot read ${infile}"; exit 1; }
mkdir -p "${outdir}"

# ERA5 forecast products (e5.oper.fc.*) have TWO time dimensions: the record
# dimension forecast_initial_time and, inside each record, forecast_hour.  ncra
# reduces only the record dimension, so the mean and maximum are finished over
# forecast_hour with ncwa.  ncwa loads the whole array, but by then the array is
# the small regional result, so that costs nothing.  Analysis products
# (e5.oper.an.*) have a single time dimension and skip this.
inner_time_dim="${INNER_TIME_DIM:-forecast_hour}"
if ! ncks --cdl -m "${infile}" 2>/dev/null | grep -Eq "^[[:space:]]+${inner_time_dim} = "; then
    inner_time_dim=""
fi

# Averaging or taking the maximum of these over time gives numbers that look
# like data but mean nothing -- the "mean" of yyyymmddhh dates, the "mean"
# forecast hour -- so the mean and max drop them.  The time series keeps them.
# forecast_initial_time stays: its mean is the middle of the period.
meaningless="utc_date ${inner_time_dim}"

# drop_meaningless <file>: remove those of ${meaningless} that <file> has
drop_meaningless() {
    local f="$1" hdr drop="" v
    hdr=$(ncks --cdl -m "${f}" 2>/dev/null)
    for v in ${meaningless}; do
        echo "${hdr}" | grep -Eq "^[[:space:]]+[a-z0-9 ]+ ${v}( ;|\()" && drop="${drop:+${drop},}${v}"
    done
    [ -z "${drop}" ] && return 0
    ncks -O -x -v "${drop}" "${f}" "${f}.2" && mv -f "${f}.2" "${f}"
}

# MEASURE=1 records each operation's peak resident memory and elapsed time.
# Each process writes its OWN file under <outdir>/mem/ -- every step's three
# ops all appending to one log would race on a parallel filesystem.
#
# Summarize a finished run with:
#
#   cat out.unpinned/mem/*.log | awk -F'|' '
#       {g=$1/1048576; t+=g; if(g>m)m=g}
#       END {printf "%d ops, largest %.2f GB, mean %.2f GB\n", NR, m, t/NR}'
#
base=$(basename "${infile}" .nc)
memdir=""
if [ -n "${MEASURE:-}" ]; then
    if [ -x /usr/bin/time ]; then
        memdir="${outdir}/mem"
        mkdir -p "${memdir}"
    else
        echo "warning: MEASURE=1 but /usr/bin/time not found; not measuring" >&2
    fi
fi

# WATCH_CORES=<seconds> checks the placement directly.  Every <seconds> it
# records, for each NCO process this step has running,
#
#   * the core it is on now   (ps -o psr: the core it last ran on)
#   * the cores it may use    (Cpus_allowed_list in /proc/<pid>/status, which
#                              is what taskset sets)
#
# in <outdir>/cores/<base>.log, and adds a summary to the step's own log:
#
#   cores: mean/ncra     allowed 0-2      ran on 0,2       (18 samples)
#
# Pinned, every process should be allowed only its step's three cores and stay
# on them; unpinned, each is allowed the whole node.  A sample costs one ps per
# step, so keep the interval at a second or more.  Like MEASURE, set it in
# config_env.sh, which is sourced on the compute node.
#
# See how a whole run was placed with:
#
#   grep -h '^cores:' stdout-<job id>/step-*.out | awk '{print $2, $4}' | sort | uniq -c
#
corelog=""
if [ -n "${WATCH_CORES:-}" ]; then
    mkdir -p "${outdir}/cores"
    corelog="${outdir}/cores/${base}.log"
    : > "${corelog}"
fi

# watch_cores: until killed, append one line per sample per NCO process
# descended from this step:   <seconds> <pid> <op> <core> <allowed cores>
watch_cores() {
    local t0 now
    t0=$(date +%s.%N)
    while :; do
        now=$(date +%s.%N)
        ps -e -o pid=,ppid=,psr=,args= | awk -v top=$$ -v t0="${t0}" -v now="${now}" '
            {
                parent[$1] = $2; core[$1] = $3
                prog[$1] = $4; sub(/.*\//, "", prog[$1])
                out[$1] = $NF
            }
            END {
                for (p in prog) {
                    if (prog[p] !~ /^nc/) continue
                    a = p
                    while ((a in parent) && a != top) a = parent[a]
                    if (a != top) continue
                    # which reduction: the output it is writing names it
                    kind = "?"
                    if (match(out[p], /[.](mean|max|series)[.]tmp/))
                        kind = substr(out[p], RSTART + 1, RLENGTH - 5)
                    allowed = ""
                    f = "/proc/" p "/status"
                    while ((getline line < f) > 0)
                        if (line ~ /^Cpus_allowed_list:/) { split(line, w, /[ \t]+/); allowed = w[2] }
                    close(f)
                    # gone since ps listed it: its psr is stale, so skip it
                    if (allowed == "") continue
                    printf "%.1f %s %s/%s %s %s\n", now - t0, p, kind, prog[p], core[p], allowed
                }
            }' >> "${corelog}"
        sleep "${WATCH_CORES}"
    done
}

# summarize_cores: one line per operation -- the cores it was allowed and the
# cores it was seen on.  Lines are per operation, not per pid: a process caught
# between fork and exec (NCO starting a helper, say) shows up briefly under its
# parent's name with a pid of its own, and is the same operation.
summarize_cores() {
    awk '
        { op = $3; n[op]++
          if (!((op, $5) in seen_a)) { seen_a[op, $5] = 1; allowed[op] = allowed[op] (allowed[op] == "" ? "" : ";") $5 }
          if (!((op, $4) in seen_c)) { seen_c[op, $4] = 1; nc[op]++; c[op, nc[op]] = $4 + 0 } }
        END {
            for (op in n) {
                # the cores seen, in numerical order
                for (i = 2; i <= nc[op]; i++)
                    for (j = i; j > 1 && c[op, j - 1] > c[op, j]; j--) {
                        t = c[op, j]; c[op, j] = c[op, j - 1]; c[op, j - 1] = t }
                on = c[op, 1]; for (i = 2; i <= nc[op]; i++) on = on "," c[op, i]
                printf "cores: %-14s allowed %-8s ran on %-10s (%d samples)\n", op, allowed[op], on, n[op]
            }
        }' "${corelog}" | sort
}

region="-d latitude,${lat_range} -d longitude,${lon_range}"

# reduce <name> <ncwa options, or "" for none> <NCO operator and options...>
#
# Runs one operation on this step's input into <base>.<name>.nc.  The work is
# done under a temporary name and renamed only once it has succeeded; any
# output left by an earlier run is removed first, so a failure leaves nothing
# for gather.sh to pick up by mistake.
reduce() {
    local name="$1" inner="$2"; shift 2
    local out="${outdir}/${base}.${name}.nc"
    local tmp="${outdir}/${base}.${name}.tmp"
    local meas=""
    [ -n "${memdir}" ] && meas="/usr/bin/time -f %M|%e|%C -o ${memdir}/${base}.${name}.log"
    rm -f "${out}"

    if ! ${meas} "$@" ${region} "${infile}" "${tmp}"; then
        echo "ERROR: ${name}: $* failed on ${infile}" >&2
        rm -f "${tmp}"
        return 1
    fi
    if [ -n "${inner}" ] && [ -n "${inner_time_dim}" ]; then
        if ! ncwa -O -a "${inner_time_dim}" ${inner} "${tmp}" "${tmp}.2"; then
            echo "ERROR: ${name}: ncwa over ${inner_time_dim} failed" >&2
            rm -f "${tmp}" "${tmp}.2"
            return 1
        fi
        mv -f "${tmp}.2" "${tmp}"
    fi
    if [ -n "${inner}" ] && ! drop_meaningless "${tmp}"; then
        echo "ERROR: ${name}: could not drop ${meaningless}" >&2
        rm -f "${tmp}" "${tmp}.2"
        return 1
    fi
    mv -f "${tmp}" "${out}"
}

start=$(date +%s.%N)

watcher=""
if [ -n "${corelog}" ]; then
    watch_cores &
    watcher=$!
fi

pids=() ; names=()
reduce mean   "-y avg" ncra -O        & pids+=($!) ; names+=(mean)
reduce max    "-y max" ncra -O -y max & pids+=($!) ; names+=(max)
reduce series ""       ncks -O        & pids+=($!) ; names+=(series)

# wait for each of this step's three reductions, noting any that failed
failed=()
for i in "${!pids[@]}"; do
    wait "${pids[$i]}" || failed+=("${names[$i]}")
done

secs=$(awk -v a="${start}" -v b="$(date +%s.%N)" 'BEGIN {printf "%.2f", b-a}')
echo "step ${base} | ops 3 | failed ${#failed[@]} | seconds ${secs} | host $(hostname -s) | PBS_ARRAY_INDEX=${PBS_ARRAY_INDEX:-0}"

if [ -n "${watcher}" ]; then
    kill "${watcher}" 2>/dev/null
    wait "${watcher}" 2>/dev/null
    summarize_cores
fi

if [ ${#failed[@]} -gt 0 ]; then
    echo "ERROR: ${base}: failed: ${failed[*]}" >&2
    exit 1
fi
exit 0
