#!/bin/bash

export PATH=/glade/derecho/scratch/kedziora/pbstools/bin:$PATH

launch_cf -q develop -l walltime=0:05:00 -A $PBS_ACCOUNT --steps-per-node 32 --nthreads 4 ./cmdfile.unbound |& tee launch_cf.unbound.log
