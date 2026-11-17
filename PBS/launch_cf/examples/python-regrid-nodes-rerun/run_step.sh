#!/usr/bin/bash
#
# One step: one ensemble member of calc_anomaly_numba.py, timed by /usr/bin/time.
# The thread count and numactl placement come from the command file.
#
# Usage:  ./run_step.sh <member> [iterations]
#
# More iterations make a longer step: about 0.05 s each when a node runs 16
# steps at once.

member="$1"
iters="${2:-40}"

/usr/bin/time -f "Elapsed time: %E | Max RSS: %M KB | Major faults: %F | Swaps: %W | \
Waits (Voluntary context switches): %w | Involuntary context switches: %c" \
 ./calc_anomaly_numba.py --member "${member}" --iters "${iters}"
