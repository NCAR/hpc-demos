#!/bin/bash

export OMP_NUM_THREADS=1

launch_cf -A $PBS_ACCOUNT -l walltime=00:10:00 ./cmdfile |& tee launch_cf.log
