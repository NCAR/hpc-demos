#!/usr/bin/bash
#
# One step of make_climo.sh: one calendar day of the climatology, timed by
# /usr/bin/time.  The thread count and numactl placement come from the
# command file.
#
# Usage:  ./run_climo_day.sh <MMDD> [more make_climo_day.py arguments]

/usr/bin/time -f "Elapsed time: %E | Max RSS: %M KB | Major faults: %F | Swaps: %W | \
Waits (Voluntary context switches): %w | Involuntary context switches: %c" \
 ./make_climo_day.py "$@"
