#!/bin/bash
#PBS -N numa_test
#PBS -q main
#PBS -l select=1:ncpus=128
#PBS -l walltime=00:30:00
#PBS -j oe
#
# Does placement change the speed of a threaded, memory-bound Python
# computation on ERA5 data?
#
# Every process runs climatology.py with 16 threads over one month of hourly
# ERA5 2 m temperature (744 x 721 x 1440 float32, 3.1 GB), held in memory.
# Eight of them fill a node, one per NUMA domain, as launch_cf would run 8
# steps of 16 threads.  They load first and then compute together for
# <seconds>, so they compete for memory bandwidth the whole time.  Cases:
#
#   8 free        no placement at all.  The main thread reads the array, so
#                 all of it sits in that thread's domain, and the scheduler
#                 puts the 16 compute threads wherever it likes
#   8 touch       as free, but each thread copies its own band first, so its
#                 pages start out where it is (the fix in code, no numactl)
#   8 bind        numactl --cpunodebind=d --membind=d: threads and memory in
#                 the process's own domain d
#   8 bind+pin    as bind, and each thread pinned to its own core
#   8 interleave  numactl --cpunodebind=d --interleave=all: threads in d,
#                 memory spread over all 8 domains
#   1 free        one process alone on the node, unpinned
#   1 bind        one process alone, bound to domain 0
#
# The last two show why this has to be measured on a full node: a process
# alone has the node's memory system to itself, so its placement hardly matters.
#
# A warm-up run comes first, and each case repeats <repeats> times in a rotated
# order so no case always runs first.  Each run prints the node's total
# throughput, the range over its processes, and "local": the share of the
# threads' time spent on the domain that holds their data.  Every process's
# own report line goes to numa_test.<host>.<time>.log, with the domains its
# threads ran on and its memory sits in.
#
# Run it on a compute node, interactively or as a batch job:
#
#   qsub -I -A $PBS_ACCOUNT -q main -l select=1:ncpus=128 -l walltime=00:30:00
#   ./numa_test.sh [repeats] [seconds]       defaults 3 and 20
#
#   qsub -A $PBS_ACCOUNT numa_test.sh        (repeats and seconds as above)
#
# Environment:
#   ERA5_FILE=<file>   a different input (any NetCDF file with a 3-D field)
#   ERA5_MONTH=YYYYMM  the month of 2 m temperature to use (default 202001)
#   SYNTHETIC=744      random data of that many time steps instead of ERA5
#   NPL_ENV=<env>      conda environment to activate (default npl-2026a)
#   NPROCS=8 THREADS=16  processes per node and threads per process, for a
#                      node whose NUMA domains are not 8 of 16 cores

set -u
reps="${1:-3}"
secs="${2:-20}"
nprocs="${NPROCS:-8}"        # NUMA domains per node: one process each
threads="${THREADS:-16}"     # cores per NUMA domain: one thread each

# a batch job starts in $HOME; run from the directory it was submitted from
if [ "${PBS_ENVIRONMENT:-}" = PBS_BATCH ]; then
    cd "${PBS_O_WORKDIR}" || exit 1
else
    cd "$(dirname "$0")" || exit 1
fi

if ! python3 -c 'import numpy, netCDF4' 2>/dev/null; then
    module load conda 2>/dev/null && conda activate "${NPL_ENV:-npl-2026a}"
fi
python3 -c 'import numpy, netCDF4' 2>/dev/null ||
    { echo "ERROR: no NumPy/netCDF4 -- module load conda; conda activate ${NPL_ENV:-npl-2026a}"; exit 1; }
command -v numactl >/dev/null || { echo "ERROR: needs numactl"; exit 1; }

src=()
if [ -n "${SYNTHETIC:-}" ]; then
    src=(--synthetic "${SYNTHETIC}")
else
    if [ -z "${ERA5_FILE:-}" ]; then
        for root in /glade/campaign/collections/gdex/data /gdex/data \
                    /glade/campaign/collections/rda/data; do
            ERA5_FILE=$(ls "${root}"/d633000/e5.oper.an.sfc/"${ERA5_MONTH:-202001}"/e5.oper.an.sfc.128_167_2t.ll025sc.*.nc 2>/dev/null | head -1)
            [ -n "${ERA5_FILE}" ] && break
        done
    fi
    [ -r "${ERA5_FILE:-}" ] ||
        { echo "ERROR: no ERA5 2 m temperature file -- set ERA5_FILE, or SYNTHETIC=744"; exit 1; }
    src=(--file "${ERA5_FILE}")
fi

work="/dev/shm/numa_test.$$"
mkdir -p "${work}"
trap 'rm -rf "${work}"' EXIT
cache="${work}/field.npy"
log="numa_test.$(hostname -s).$(date +%Y%m%d-%H%M%S).log"

# Read the input once, into /dev/shm.  Every run then loads it from memory in
# a second or two, instead of paying for GLADE and decompression again.
python3 climatology.py "${src[@]}" --cache "${cache}" --prepare || exit 1

# nproc would report OMP_NUM_THREADS, not the CPUs this shell may use
cpus=$(awk '/^Cpus_allowed_list:/ {print $2}' /proc/self/status 2>/dev/null)
echo "host $(hostname -s), CPUs ${cpus:-?} available, $(ls /sys/devices/system/node | grep -c '^node[0-9]') NUMA domains"
echo "input ${ERA5_FILE:-synthetic}, $(du -m "${cache}" | cut -f1) MB in memory per process"
echo "kernel NUMA balancing $(cat /proc/sys/kernel/numa_balancing 2>/dev/null || echo ?)" \
     "(1 = the kernel migrates pages toward the threads using them)," \
     "transparent huge pages $(grep -o '\[[a-z]*\]' /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)"
echo "${threads} threads per process, ${secs} s of compute per run; details in ${log}"
echo

# run <processes> <variant>
run() {
    local n=$1 v=$2 d pre extra
    rm -rf "${work}/sync" "${work}"/out.*
    mkdir "${work}/sync"
    for (( d = 0; d < n; d++ )); do
        pre=""; extra=""
        case ${v} in
            touch)      extra="--first-touch threads" ;;
            bind)       pre="numactl --cpunodebind=${d} --membind=${d}" ;;
            bind+pin)   pre="numactl --cpunodebind=${d} --membind=${d}"
                        extra="--pin-threads" ;;
            interleave) pre="numactl --cpunodebind=${d} --interleave=all" ;;
        esac
        ${pre} python3 climatology.py --cache "${cache}" --threads ${threads} \
            --seconds "${secs}" --sync "${work}/sync" --nprocs "${n}" \
            --label "${v}" --step "${d}" ${extra} > "${work}/out.${d}" &
    done
    wait

    cat "${work}"/out.* >> "${log}"
    cat "${work}"/out.* | awk -v n="${n}" -v v="${v}" '
        {
            for (i = 1; i <= NF; i++) { split($i, kv, "="); f[kv[1]] = kv[2] }
            g = f["GBps"] + 0; sum += g; ok++
            if (ok == 1 || g < lo) lo = g
            if (ok == 1 || g > hi) hi = g
            if (f["local"] != "?") { loc += f["local"]; nloc++ }
        }
        END {
            printf "%d %-10s  node %6.1f GB/s  |  per process %5.1f - %5.1f GB/s  |  local %s%s\n",
                n, v, sum, lo, hi, (nloc ? sprintf("%3.0f%%", loc / nloc) : "  ?"),
                (ok < n ? sprintf("  |  %d FAILED", n - ok) : "")
        }'
}

echo "warm-up:"
echo "# warm-up" >> "${log}"
run ${nprocs} free
echo

cases=("${nprocs} free" "${nprocs} touch" "${nprocs} bind" "${nprocs} bind+pin"
       "${nprocs} interleave" "1 free" "1 bind")
for (( r = 0; r < reps; r++ )); do
    echo "repeat $(( r + 1 )):"
    echo "# repeat $(( r + 1 ))" >> "${log}"
    for (( k = 0; k < ${#cases[@]}; k++ )); do
        run ${cases[$(( (k + r) % ${#cases[@]} ))]}
    done
    echo
done
