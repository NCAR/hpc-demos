#!/bin/bash

# Pinned: every step, and the three NCO processes it starts, are confined to
# that step's own block of three cores.  Once both runs have finished, compare
# their step times with
#
#   ./compare_runs.sh
#
# which reads the job ids from launch_cf.log and launch_cf.pinned.log.

# launch_cf passes an argument that is not a file on to qsub, so a missing
# command file surfaces only as a qsub usage message -- check for it here
[ -r ./cmdfile.pinned ] || { echo "ERROR: no ./cmdfile.pinned -- run ./gen_cmdfile_postproc.sh pin first"; exit 1; }

launch_cf -A $PBS_ACCOUNT -l walltime=00:20:00 \
  --nthreads 3 \
  ./cmdfile.pinned |& tee launch_cf.pinned.log
