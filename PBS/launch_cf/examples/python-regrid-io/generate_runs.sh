#!/usr/bin/env bash
# generate_cmdfiles.sh
# Generates bound and unbound launch_cf command files for a 128-core Derecho node.

set -euo pipefail

# Configuration:
# Each AMD EPYC Milan CCX (L3 cache group) has 8 cores; placing 1 task (4 threads) per 8-core stride
# gives every task dedicated L3 cache and balanced memory channel access across both sockets.
NUM_TASKS=32
THREADS_PER_TASK=8
CORES_PER_NODE=128
NUMA_PER_NODE=8

CORE_STRIDE=$(( CORES_PER_NODE / NUM_TASKS ))  # 128 / 32 = 4 cores per task slot (or set NUM_TASKS=16 for 8-core stride)

UNBOUND_FILE="cmdfile.unbound"
BOUND_FILE="cmdfile.bound"

> "$UNBOUND_FILE"
> "$BOUND_FILE"

for (( i=0; i<NUM_TASKS; i++ )); do
    MEMBER=$(( i + 1 ))
    
    numa_node=$(( i % NUMA_PER_NODE ))  

    # 1. Unbound (OS scheduler floats threads across sockets/caches)
    echo "OMP_NUM_THREADS=${THREADS_PER_TASK} OPENBLAS_NUM_THREADS=${THREADS_PER_TASK} MKL_NUM_THREADS=${THREADS_PER_TASK} ./run_step.sh ${MEMBER}" >> "$UNBOUND_FILE"

    # 2. Optimally Bound (Pinned to dedicated physical cores + strict local NUMA memory allocation)
    echo "OMP_NUM_THREADS=${THREADS_PER_TASK} OPENBLAS_NUM_THREADS=${THREADS_PER_TASK} MKL_NUM_THREADS=${THREADS_PER_TASK} numactl --cpunodebind=$numa_node --membind=$numa_node ./run_step.sh ${MEMBER}" >> "$BOUND_FILE"

done

# This will run all the steps on one node
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

# This will use multple subjobs if NUM_TASKS exceeds the number of tasks per node
TASKS_PER_NODE=$(( 128 / THREADS_PER_TASK ))
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
