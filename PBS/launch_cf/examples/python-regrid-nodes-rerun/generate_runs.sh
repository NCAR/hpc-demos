#!/usr/bin/env bash
# generate_runs.sh
# Writes the two command files of this example:
#
#   cmdfile.short   32 steps of a few seconds each: for trying --nodes
#   cmdfile.medium  32 steps of about 2 minutes each: for trying --rerun on
#                  the develop queue, with a node taken back by hand
#   cmdfile.long   256 steps of about 5 minutes each: for the preempt queue
#                  and --rerun
#
# Every step runs 8 threads, kept in one NUMA domain with numactl.  A node
# runs 16 such steps at once, 2 in each of its 8 domains; the domain counts
# 0-7 down the file.

set -euo pipefail

THREADS_PER_TASK=8           # threads per step
NUMA_PER_NODE=8              # NUMA domains per Derecho CPU node

SHORT_TASKS=32               # steps in cmdfile.short
SHORT_ITERS=40               # iterations per step: about 2 s of computing

MEDIUM_TASKS=32              # steps in cmdfile.medium
MEDIUM_ITERS=2000            # iterations per step: about 2 minutes of computing

LONG_TASKS=256               # steps in cmdfile.long
LONG_ITERS=6000              # iterations per step: about 5 minutes of computing

# write_cmdfile <file> <steps> <iterations per step>
write_cmdfile ()
{
    local file=$1 ntasks=$2 iters=$3 i d
    > "${file}"
    for (( i=0; i<ntasks; i++ )); do
        d=$(( i % NUMA_PER_NODE ))
        echo "OMP_NUM_THREADS=${THREADS_PER_TASK} numactl --cpunodebind=${d} --membind=${d} ./run_step.sh $(( i + 1 )) ${iters}" >> "${file}"
    done
    echo "Wrote ${file}: ${ntasks} steps of ${iters} iterations"
}

write_cmdfile cmdfile.short ${SHORT_TASKS} ${SHORT_ITERS}
write_cmdfile cmdfile.medium ${MEDIUM_TASKS} ${MEDIUM_ITERS}
write_cmdfile cmdfile.long  ${LONG_TASKS}  ${LONG_ITERS}
