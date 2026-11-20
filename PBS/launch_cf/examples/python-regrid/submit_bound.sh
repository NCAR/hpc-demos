#!/bin/bash

export PATH=/glade/derecho/scratch/kedziora/pbstools/bin:$PATH

launch_cf -q develop -l walltime=0:05:00 -A $PBS_ACCOUNT --steps-per-node 16   --nthreads 8 ./cmdfile.bound |& tee launch_cf.bound.log
