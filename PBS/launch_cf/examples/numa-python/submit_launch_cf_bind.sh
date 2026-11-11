#!/bin/bash

# Bound: numactl keeps each step's threads and memory in its own NUMA domain.
# Once both runs have finished, compare their steps with
#
#   ./compare_runs.sh
#
# which reads the job ids from launch_cf.log and launch_cf.bind.log.

# launch_cf passes an argument that is not a file on to qsub, so a missing
# command file surfaces only as a qsub usage message -- check for it here
[ -r ./cmdfile.bind ] || { echo "ERROR: no ./cmdfile.bind -- run ./gen_cmdfile_numa.sh bind first"; exit 1; }

launch_cf -A $PBS_ACCOUNT -l walltime=00:20:00 \
  --nthreads 16 --steps-per-node 8 \
  ./cmdfile.bind |& tee launch_cf.bind.log
