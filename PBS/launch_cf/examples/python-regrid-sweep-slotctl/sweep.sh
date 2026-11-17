#!/usr/bin/env bash
#
# sweep.sh: for each thread count, run the same steps as a job array of
# MAX_NODES nodes in 1 wave each, down to 1 node in MAX_NODES waves -- each
# as an unbound and a bound run.
#
# A packed node runs 128 / threads steps at once.  Each thread count gets
# MAX_NODES (default 8) times that many steps, spread as:
#
#   threads  at once  steps  1 wave   2 waves   4 waves   8 waves
#      2        64     512   8 nodes  4 nodes   2 nodes   1 node
#      4        32     256   8 nodes  4 nodes   2 nodes   1 node
#      8        16     128   8 nodes  4 nodes   2 nodes   1 node
#
# So every column does the same work for a thread count, with fewer nodes
# and more waves to the right.  Every step does the same work whatever its
# threads, so a 2-thread row has 4 times the work of an 8-thread row: compare
# rows by node-seconds per step (summarize.py), not by run time.
#
# That is 3 x 4 x 2 = 24 jobs, 90 node-jobs in all.  Runs of more than 2
# nodes go to the main queue (see submit_runs.sh).
#
# Environment (and anything submit_runs.sh takes, e.g. PLACEMENTS, DRYRUN):
#   THREADS="2 4 8"
#   WAVES="1 2 4 8"     each must divide MAX_NODES
#   MAX_NODES=8

set -euo pipefail
cd "$(dirname "$0")"

CORES_PER_NODE=128
max_nodes="${MAX_NODES:-8}"
for threads in ${THREADS:-2 4 8}; do
    nsteps=$(( max_nodes * CORES_PER_NODE / threads ))
    for waves in ${WAVES:-1 2 4 8}; do
        ./submit_runs.sh "${threads}" "${nsteps}" "${waves}"
    done
done
