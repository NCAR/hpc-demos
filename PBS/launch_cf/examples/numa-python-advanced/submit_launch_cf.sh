#!/bin/bash

# Unbound: the Linux scheduler decides where each step's 16 threads run, and
# each step's memory lands wherever its main thread was when it read the file.

# launch_cf passes an argument that is not a file on to qsub, so a missing
# command file surfaces only as a qsub usage message -- check for it here
[ -r ./cmdfile ] || { echo "ERROR: no ./cmdfile -- run ./gen_cmdfile_numa.sh first"; exit 1; }

launch_cf -A $PBS_ACCOUNT -l walltime=00:20:00 \
  --nthreads 16 --steps-per-node 8 \
  ./cmdfile |& tee launch_cf.log
