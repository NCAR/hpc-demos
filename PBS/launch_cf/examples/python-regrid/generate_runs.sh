#!/usr/bin/env bash
# generate_runs.sh
# Writes the bound and unbound launch_cf command files for 128-core Derecho
# nodes, and the four scripts that submit them:
#
#   submit_unbound.sh, submit_bound.sh              as many nodes as needed,
#                                                   every step at once
#   submit_unbound_waves.sh, submit_bound_waves.sh  all steps on one node,
#                                                   as many at once as fit
#
# A node runs 128 / THREADS_PER_TASK steps at once: 16 of 8 threads, so 2 per
# 16-core NUMA domain.  In the bound file the domain counts 0-7 down the file.

set -euo pipefail

# Configuration:
NUM_TASKS=32                 # steps (ensemble members) == lines in each command file
THREADS_PER_TASK=8           # threads per step
CORES_PER_NODE=128
NUMA_PER_NODE=8              # NUMA domains per node

UNBOUND_FILE="cmdfile.unbound"
BOUND_FILE="cmdfile.bound"

> "$UNBOUND_FILE"
> "$BOUND_FILE"

for (( i=0; i<NUM_TASKS; i++ )); do
    MEMBER=$(( i + 1 ))
    
    numa_node=$(( i % NUMA_PER_NODE ))  

    # 1. Unbound: Linux places the threads and memory, and may move the threads
    echo "OMP_NUM_THREADS=${THREADS_PER_TASK} OPENBLAS_NUM_THREADS=${THREADS_PER_TASK} MKL_NUM_THREADS=${THREADS_PER_TASK} ./run_step.sh ${MEMBER}" >> "$UNBOUND_FILE"

    # 2. Bound: threads and memory kept in one NUMA domain, 2 steps per domain.
    #    numactl picks the domain, not the core: Linux still places the threads
    #    among its 16 cores.
    echo "OMP_NUM_THREADS=${THREADS_PER_TASK} OPENBLAS_NUM_THREADS=${THREADS_PER_TASK} MKL_NUM_THREADS=${THREADS_PER_TASK} numactl --cpunodebind=$numa_node --membind=$numa_node ./run_step.sh ${MEMBER}" >> "$BOUND_FILE"

done

# All the steps on one node: a new step starts each time one finishes.
# (Needs a launch_cf that runs steps in waves.)
cat>submit_bound_waves.sh<<eof
#!/bin/bash

export PATH=/glade/derecho/scratch/kedziora/pbstools/bin:\$PATH

launch_cf -q develop -l walltime=0:05:00 -A \$PBS_ACCOUNT --steps-per-node $NUM_TASKS \
  --nthreads $THREADS_PER_TASK ./cmdfile.bound |& tee launch_cf.bound_waves.log
eof
cat>submit_unbound_waves.sh<<eof
#!/bin/bash

export PATH=/glade/derecho/scratch/kedziora/pbstools/bin:\$PATH

launch_cf -q develop -l walltime=0:05:00 -A \$PBS_ACCOUNT --steps-per-node $NUM_TASKS \
  --nthreads $THREADS_PER_TASK ./cmdfile.unbound |& tee launch_cf.unbound_waves.log
eof

# One node per TASKS_PER_NODE steps, all running at once (a job array if
# NUM_TASKS needs more than one node)
TASKS_PER_NODE=$(( CORES_PER_NODE / THREADS_PER_TASK ))
cat>submit_bound.sh<<eof
#!/bin/bash

export PATH=/glade/derecho/scratch/kedziora/pbstools/bin:\$PATH

launch_cf -q develop -l walltime=0:05:00 -A \$PBS_ACCOUNT --steps-per-node $TASKS_PER_NODE \
  --nthreads $THREADS_PER_TASK ./cmdfile.bound |& tee launch_cf.bound.log
eof

cat>submit_unbound.sh<<eof
#!/bin/bash

export PATH=/glade/derecho/scratch/kedziora/pbstools/bin:\$PATH

launch_cf -q develop -l walltime=0:05:00 -A \$PBS_ACCOUNT --steps-per-node $TASKS_PER_NODE \
  --nthreads $THREADS_PER_TASK ./cmdfile.unbound |& tee launch_cf.unbound.log
eof
chmod u+x submit_bound_waves.sh
chmod u+x submit_unbound_waves.sh
chmod u+x submit_bound.sh
chmod u+x submit_unbound.sh
