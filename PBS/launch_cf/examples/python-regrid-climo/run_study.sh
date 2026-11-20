#!/usr/bin/env bash
#
# run_study.sh [first file]
#
# The study of 16 Nov 2026: the one-pass climatology script with its two
# readers, climoh5 (h5py) and climo (parallel decompression), as one chain
# of jobs, each held until the one before it has ended so no two share the
# file system:
#
#   1. solo.pbs: one step alone on a node, 1-128 threads, uncached and cached
#   2. one packed node, bound, 512 files: climo at 8 and 16 threads, climoh5
#      at 1, 2, 4 and 8 (climo at 1, 2 and 4 ran before, jobs 8207720-8207722)
#   3. the same 512 files as 4 nodes, 2 nodes or 1 node, bound or unbound,
#      for climo at 1, 2, 4, 8 threads and climoh5 at 1, 2 (the bound 1-node
#      runs are those of part 2)
#
# Every run reads its own files from era5_t_files.txt, starting at line
# <first file> (default 1536, the first line no run has used).
# Summarize with ./summarize_study.py.

set -euo pipefail
first="${1:-1536}"
export WALLTIME="${WALLTIME:-0:30:00}"
dep=()

jobid() { grep -oE '^[0-9]+(\[\])?\.[a-z0-9]+' "$1" | tail -1; }

# 1. one step alone
j=$(qsub -A "${PBS_ACCOUNT}" -v FIRST="${first}" solo.pbs)
echo "solo FIRST=${first}: ${j}"
dep=(-- -W "depend=afterany:${j}")
first=$(( first + 16 ))

run() {   # script placement threads nodes waves
    ./submit_study.sh "$1" "$2" "$3" "$4" "$5" "${first}" "${dep[@]}" > /dev/null
    local tag log j
    tag=$(printf "%s.%s.t%02d.n%02d.w%d.f%05d" "$1" "$2" "$3" "$4" "$5" "${first}")
    log="logs/launch_cf.${tag}.log"
    j=$(jobid "${log}")
    [ -n "${j}" ] || { echo "ERROR: no job id in ${log}"; exit 1; }
    echo "${tag}: ${j}"
    dep=(-- -W "depend=afterany:${j}")
    first=$(( first + $4 * $5 * 128 / $3 ))
}

# 2. one packed node, bound, 512 files
run climo   bound 8  1 32
run climo   bound 16 1 64
for t in 1 2 4 8; do run climoh5 bound "${t}" 1 $(( 4 * t )); done

# 3. nodes against waves, bound against unbound, 512 files each
for case in "climo 1" "climo 2" "climo 4" "climo 8" "climoh5 1" "climoh5 2"; do
    set -- ${case}
    for placement in unbound bound; do
        for nodes in 4 2 1; do
            [ "${placement}" = bound ] && [ "${nodes}" = 1 ] && continue
            run "$1" "${placement}" "$2" "${nodes}" $(( 4 * $2 / nodes ))
        done
    done
done
echo "next unused line of era5_t_files.txt: ${first}"
