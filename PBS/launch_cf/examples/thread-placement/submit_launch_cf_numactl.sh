#!/bin/bash

# Same job as ./submit_launch_cf.sh, but running the command file whose steps
# are prefixed with "numactl --cpunodebind=N --membind=N".  Compare the two
# runs with parse_steps.py: the "1-domain steps" column should go from 0 of 8
# to 8 of 8.

export OMP_NUM_THREADS=16

launch_cf -A $PBS_ACCOUNT -l walltime=00:10:00 \
  --nthreads 16 --steps-per-node 8 \
  ./cmdfile.numactl |& tee launch_cf.numactl.log
