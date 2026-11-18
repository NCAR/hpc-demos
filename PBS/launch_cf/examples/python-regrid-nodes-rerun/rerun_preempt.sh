#!/bin/bash
#
# Usage:  ./rerun_preempt.sh <job id>
#
# Once a job from submit_preempt.sh (or from an earlier rerun_preempt.sh) has
# finished, submits the steps of it that did not succeed -- those cut short
# when PBS took a node back, those that never started, and any that failed --
# again on the preempt queue.  Repeat with the new job's id until launch_cf
# reports there is nothing to rerun.
#
# Run it from the directory the job was submitted from: launch_cf --rerun reads
# the job's PBS output files and step logs there.  Run from anywhere else, it
# says which directory that is, and submits nothing.
#
# --rerun takes the command file from the job's output, and writes the steps
# to rerun to <command file>.<job id>.rerun.  The other options are not taken
# from the earlier job, so give them again; the remaining steps run 16 to a
# node, on as many nodes as they need.
#
# The output is also saved to launch_cf.rerun.<job id>.<date-time>.log.

set -o pipefail     # exit with launch_cf's status, not tee's

jobid=${1:?usage: $0 <job id>}

export PATH=/glade/derecho/scratch/kedziora/pbstools/bin:$PATH

launch_cf -q preempt -l walltime=1:00:00 -A ${PBS_ACCOUNT} --nthreads 8 \
    --steps-per-node 16 --rerun ${jobid} \
    |& tee launch_cf.rerun.${jobid%%[^0-9]*}.$(date +%Y%m%d-%H%M%S).log
