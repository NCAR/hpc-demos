#!/bin/bash

# Unpinned: the Linux scheduler decides where each step's ncks processes run.

# launch_cf passes an argument that is not a file on to qsub, so a missing
# command file surfaces only as a qsub usage message -- check for it here
[ -r ./cmdfile ] || { echo "ERROR: no ./cmdfile -- run ./gen_cmdfile_postproc.sh first"; exit 1; }

launch_cf -A $PBS_ACCOUNT -l walltime=00:20:00 \
  --nthreads 3 \
  ./cmdfile |& tee launch_cf.log
