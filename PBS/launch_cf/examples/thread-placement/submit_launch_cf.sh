#!/bin/bash

export OMP_NUM_THREADS=16

launch_cf -A $PBS_ACCOUNT -l walltime=00:10:00 \
  --nthreads 16 --steps-per-node 8 \
  ./cmdfile |& tee launch_cf.log
