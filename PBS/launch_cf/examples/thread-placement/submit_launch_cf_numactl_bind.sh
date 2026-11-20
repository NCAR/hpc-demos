#!/bin/bash

# Third variant: numactl confines each step to one NUMA domain, and
# OMP_PROC_BIND/OMP_PLACES give each of its 16 threads its own physical core
# inside that domain.  Compare all three runs with parse_steps.py.

export OMP_NUM_THREADS=16

launch_cf -A $PBS_ACCOUNT -l walltime=00:10:00 \
  --nthreads 16 --steps-per-node 8 \
  ./cmdfile.numactl_bind |& tee launch_cf.numactl_bind.log
