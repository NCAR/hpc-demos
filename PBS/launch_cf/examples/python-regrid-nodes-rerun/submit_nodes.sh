#!/bin/bash
#
# Usage:  ./submit_nodes.sh <number of nodes>
#
# Runs the 32 steps of cmdfile.short on that many nodes of the develop queue.
# launch_cf works out the steps per node; with fewer than 2 nodes, a node runs
# more steps than fit at once, and starts the next each time one finishes.

nodes=${1:?usage: $0 <number of nodes>}

export PATH=/glade/derecho/scratch/kedziora/pbstools/bin:$PATH

launch_cf -q develop -l walltime=0:05:00 -A ${PBS_ACCOUNT} --nthreads 8 \
    --nodes ${nodes} ./cmdfile.short |& tee launch_cf.nodes${nodes}.log
