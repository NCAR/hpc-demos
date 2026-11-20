#!/bin/bash
#
# Does SMT add throughput to CPU-bound NCO work, and does pinning matter?
#
# Every process recompresses the same file at deflate level 6, reading it from
# and writing to /dev/shm, so the filesystem is out of the picture and the work
# is zlib: CPU-bound integer code.  Four cases:
#
#   128 pin    one process per physical core (CPUs 0-127)
#   128 free   the same 128, placed by the scheduler
#   256 pin    two per physical core (CPU i and its sibling i+128)
#   256 free   the same 256, placed by the scheduler
#
# A warm-up run comes first, so the first measured case does not pay for
# loading NCO's libraries from GLADE.  Then each case runs <repeats> times, in
# a rotated order so no case always runs first.
#
# For each run it prints the wall time and files/s, and also each process's own
# elapsed time (median and max).  Wall time is set by the slowest process, so a
# few slow ones -- on cores the OS is also using, say -- show up as a max far
# above the median, and for pinned runs the CPU of the slowest is named.
#
# Run it as a script on a compute node (not with "source", which adds a job
# control line per process):
#
#   ./smt_test.sh [repeats]          default 3

set -u
reps="${1:-3}"

command -v ncks >/dev/null || module load nco 2>/dev/null
command -v ncks >/dev/null || { echo "ERROR: NCO not loaded -- module load nco"; exit 1; }
[ -x /usr/bin/time ] || { echo "ERROR: needs /usr/bin/time"; exit 1; }

src=$(ls data/*.nc 2>/dev/null | head -1)
[ -n "${src}" ] || { echo "ERROR: no data/*.nc -- run ./make_data.sh first"; exit 1; }

work="/dev/shm/smt_test.$$"
mkdir -p "${work}"
trap 'rm -rf "${work}"' EXIT
cp -L "${src}" "${work}/in.nc"

# nproc would report OMP_NUM_THREADS (which PBS sets to 1 unless ompthreads is
# requested), not the CPUs this shell may use, so read the affinity itself
cpus=$(awk '/^Cpus_allowed_list:/ {print $2}' /proc/self/status 2>/dev/null)
echo "host $(hostname -s), CPUs ${cpus:-?} available, input ${src}"
echo

# run <processes> <pin|free>
run() {
    local n=$1 mode=$2 i pre start launched end
    rm -f "${work}"/*.t "${work}"/out.*.nc
    start=$(date +%s.%N)
    for (( i = 0; i < n; i++ )); do
        pre=""; [ "${mode}" = pin ] && pre="taskset -c ${i}"
        ${pre} /usr/bin/time -f "${i} %e" -o "${work}/${i}.t" \
            ncks -O -4 -L 6 -d forecast_initial_time,0,4 "${work}/in.nc" "${work}/out.${i}.nc" &
    done
    launched=$(date +%s.%N)
    wait
    end=$(date +%s.%N)

    failed=$(grep -l 'non-zero status' "${work}"/*.t 2>/dev/null | wc -l | tr -d ' ')
    for f in "${work}"/*.t; do tail -1 "${f}"; done | sort -k2 -n | awk \
        -v n="${n}" -v m="${mode}" -v a="${start}" -v l="${launched}" -v b="${end}" -v bad="${failed}" '
        { cpu[NR] = $1; t[NR] = $2 }
        END {
            med = (NR % 2) ? t[(NR + 1) / 2] : (t[NR / 2] + t[NR / 2 + 1]) / 2
            printf "%3d %-4s  wall %5.1f s  %5.1f files/s  |  per process: median %4.1f s, max %4.1f s%s  |  launch %.1f s%s\n",
                n, m, b - a, n / (b - a), med, t[NR], (m == "pin" ? sprintf(" (CPU %d)", cpu[NR]) : ""),
                l - a, (bad > 0 ? sprintf("  |  %d FAILED", bad) : "")
        }'
}

echo "warm-up:"
run 128 free
echo

cases=("128 pin" "128 free" "256 pin" "256 free")
for (( r = 0; r < reps; r++ )); do
    echo "repeat $(( r + 1 )):"
    for (( k = 0; k < ${#cases[@]}; k++ )); do
        run ${cases[$(( (k + r) % ${#cases[@]} ))]}
    done
    echo
done
