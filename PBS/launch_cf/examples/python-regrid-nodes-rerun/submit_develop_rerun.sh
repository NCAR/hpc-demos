#!/bin/bash
#
# Usage:  ./submit_develop_rerun.sh               submit the job
#         ./submit_develop_rerun.sh <job id>      once it has finished, rerun
#                                                 the steps that did not succeed
#
# Tries --rerun on the develop queue, without waiting for a preemption: runs
# the 32 steps of cmdfile.medium on 2 nodes, 16 to a node.  While it runs,
# take one node away as a preemption would, with
#     qdel '<job id>[1]'
# then, when the job has finished, give its id to this script to rerun the
# 16 steps that node did not finish.  Run both from this directory.

set -o pipefail     # exit with launch_cf's status, not tee's

export PATH=/glade/derecho/scratch/kedziora/pbstools/bin:$PATH

stamp=$(date +%Y%m%d-%H%M%S)
if [ -z "$1" ]; then
    launch_cf -q develop -l walltime=0:10:00 -A ${PBS_ACCOUNT} --nthreads 8 \
        --nodes 2 ./cmdfile.medium |& tee launch_cf.develop.${stamp}.log
else
    launch_cf -q develop -l walltime=0:10:00 -A ${PBS_ACCOUNT} --nthreads 8 \
        --nodes 1 --rerun $1 |& tee launch_cf.rerun.${1%%[^0-9]*}.${stamp}.log
fi
