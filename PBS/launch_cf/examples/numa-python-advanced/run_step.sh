#!/bin/bash
#
# One step: the mean and standard deviation of one month of ERA5, 16 threads.
#
# climatology.py reads the file, then every thread makes ${PASSES} passes over
# its band.  A real analysis would make one; the repeats stand in for heavier
# work, so the compute phase (about 35 s when bound) is long enough to measure
# next to the load.  The step's last line is climatology.py's report.
#
# The 8 steps on a node meet in a node-local directory after loading, and start
# computing together.  Loading takes a different time for each step -- GLADE is
# shared -- and without that barrier an early step could finish before a late
# one starts, so the steps would not compete for memory the way they would if
# they all had their data at once.
#
# The placement comes from the command file: a pinned step runs as
#
#     numactl --cpunodebind=d --membind=d ./run_step.sh ...
#
# and numactl's policy carries over to python3 and every thread it starts.
#
# Usage:  ./run_step.sh <label> <ERA5 file>

set -u
label="$1"
file="$2"
PASSES="${PASSES:-200}"      # to change it, export PASSES in config_env.sh
steps_per_node=8             # the barrier waits for this many steps

# PBS_JOBID is unique to each array index, so each node gets its own directory
sync="/dev/shm/numa-python-advanced.${PBS_JOBID:-manual}"
mkdir -p "${sync}"

# the month, e.g. 202001 from ...ll025sc.2020010100_2020013123.nc
month=$(basename "${file}" | grep -o '[0-9]\{10\}_' | head -1 | cut -c1-6)

exec python3 ./climatology.py --file "${file}" --threads 16 --passes "${PASSES}" \
    --sync "${sync}" --nprocs ${steps_per_node} \
    --label "${label}" --step "${month:-?}"
