#!/usr/bin/bash
#
# One step: one ensemble member of calc_anomaly_numba.py, timed by /usr/bin/time.
#
# Usage:  ./run_step.sh <unbound|bound> <member> [extra calc_anomaly_numba.py args]
#
# The command file sets, on each line:
#   OMP_NUM_THREADS  threads for this step (passed on to Numba)
#   STEPS_AT_ONCE    how many steps the node runs at once
#
# unbound: Linux places the step's threads and memory.
#
# bound:   the step takes a free "slot" on its node, 0 to STEPS_AT_ONCE-1, and
#          runs with numactl in that slot's NUMA domain (slot mod 8).  A slot is
#          a lock file in node-local /dev/shm, held with flock for as long as
#          the step runs and released when it exits.  When launch_cf starts a
#          new step in place of one that finished, the new step gets the freed
#          slot, and so the freed domain -- not the domain its line number in
#          the command file would give it, which may still be full.
#
# Besides the program's own report, the step prints its placement and when it
# started and ended (seconds since 1970), for summarize.py.

set -u
placement="$1"
member="$2"
shift 2

threads="${OMP_NUM_THREADS:?set OMP_NUM_THREADS on the command file line}"
# NumPy's own BLAS does none of the work; keep it from starting threads
export OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1

slot="-"
domain="-"
prefix=()
if [ "${placement}" = bound ]; then
    slots="${STEPS_AT_ONCE:?set STEPS_AT_ONCE on the command file line}"
    ndomains=$(ls -d /sys/devices/system/node/node[0-9]* | wc -l)
    # PBS_JOBID differs for each array index, so each node has its own slots
    lockdir="/dev/shm/regrid-sweep-slots.${PBS_JOBID:-manual}"
    mkdir -p "${lockdir}"
    for (( k = 0; k < slots; k++ )); do
        exec {fd}> "${lockdir}/slot.${k}"
        if flock -n "${fd}"; then      # got it; the lock stays held until we exit
            slot=${k}
            break
        fi
        exec {fd}>&-
    done
    if [ "${slot}" = "-" ]; then
        echo "WARNING: no free slot of ${slots}; running unbound"
    else
        domain=$(( slot % ndomains ))
        prefix=(numactl --cpunodebind=${domain} --membind=${domain})
    fi
elif [ "${placement}" != unbound ]; then
    echo "ERROR: placement must be unbound or bound, not '${placement}'"
    exit 1
fi

start=$(date +%s.%N)
/usr/bin/time -f "Elapsed time: %E | Max RSS: %M KB | Major faults: %F | Swaps: %W | \
Waits (Voluntary context switches): %w | Involuntary context switches: %c" \
    "${prefix[@]}" ./calc_anomaly_numba.py --member "${member}" "$@"
status=$?
end=$(date +%s.%N)

echo "placement=${placement} slot=${slot} domain=${domain} threads=${threads}" \
     "index=${PBS_ARRAY_INDEX:-0} host=$(hostname -s) start=${start} end=${end}"
exit ${status}
