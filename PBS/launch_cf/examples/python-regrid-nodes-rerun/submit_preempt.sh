#!/bin/bash
#
# Runs the 256 steps of cmdfile.long on 4 nodes of the preempt queue, 64
# steps per node, 16 at a time.
#
# preempt jobs run on nodes that would otherwise sit idle, and are charged
# at 0.2 of the main queue's rate.  PBS can take a node back for a job of
# higher priority, giving 10 minutes' notice, and then deletes the subjob
# that ran there: PBS does not run it again.  rerun_preempt.sh resubmits just
# the steps that did not finish.

export PATH=/glade/derecho/scratch/kedziora/pbstools/bin:$PATH

launch_cf -q preempt -l walltime=1:00:00 -A ${PBS_ACCOUNT} --nthreads 8 \
    --nodes 4 ./cmdfile.long |& tee launch_cf.preempt.log
