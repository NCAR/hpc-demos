#!/usr/bin/env bash
#
# sample_prio.sh <set> [interval seconds]
#
# Every <interval> seconds (default 60) until every job of the set in runs.csv
# has finished, records into samples/<set>/:
#
#   prio.<epoch>.txt    pbs-prio --order for every job in the cpu queue, in
#                       the order the scheduler considers them, so a job's
#                       line number is its place in line
#   qstat.<epoch>.txt   qstat -t -x for the set's jobs: every subjob's state
#
# and, once all have finished, qstat-final.<job>.json: qstat -f -t -x -F json
# of each job, with every subjob's qtime, stime and end time (PBS keeps a
# finished job's record for 72 hours).
#
# pbs-prio reads a cache that NCAR refreshes every few minutes, so
# consecutive prio files may be the same; summarize.py uses the cache time.

set -euo pipefail
[ $# -ge 1 ] || { sed -n '3,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 1; }
set_name="$1"; interval="${2:-60}"

PBS_PRIO=/glade/work/benkirk/repos/hpc-scheduling-tools/conda-env/bin/pbs-prio
FMT="{id} {user} {account} {queue} {state} {computed} {t1} {t2a} {t2b} {fairshare_factor} {eligible_time} {subjobs} {nodect} {walltime}"

out="samples/${set_name}"
mkdir -p "${out}"
mapfile -t jobs < <(awk -F, -v s="${set_name}" '$1 == s { print $6 }' runs.csv)
[ ${#jobs[@]} -gt 0 ] || { echo "ERROR: no jobs for set ${set_name} in runs.csv"; exit 1; }
echo "sampling ${#jobs[@]} jobs of set ${set_name} every ${interval} s: ${jobs[*]}"

start=$(date +%s)
while true; do
    now=$(date +%s)
    "${PBS_PRIO}" --order --debug -F "${FMT}" -f queue=cpu > "${out}/prio.${now}.txt" 2>&1 || true
    qstat -t -x "${jobs[@]}" > "${out}/qstat.${now}.txt" 2>&1 || true
    # done when no job or subjob of the set is queued, held, running or exiting
    left=$(awk '$3 == ENVIRON["USER"]' "${out}/qstat.${now}.txt" | awk '$5 ~ /^[QHRBEWTS]$/' | wc -l)
    # (qstat can report a new array as finished for a minute after qsub)
    [ "${left}" -eq 0 ] && [ $(( now - start )) -gt 300 ] && { echo "$(date): all jobs of ${set_name} finished"; break; }
    sleep "${interval}"
done

for j in "${jobs[@]}"; do
    qstat -f -t -x -F json "${j}" > "${out}/qstat-final.$(echo "${j}" | sed 's/[^0-9].*//').json" 2>/dev/null || true
done
