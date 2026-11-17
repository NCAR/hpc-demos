#!/usr/bin/bash

member="$1"

which launch_cf

/usr/bin/time -f "Elapsed time: %E\nMax RSS: %M KB\nMajor faults: %F\nSwaps: %W\n\
Waits (Voluntary context switches): %w\nInvoluntary context switche: %c" \
 ./calc_anomaly.py --member "${member}"

#/usr/bin/time -v ./calc_anomaly.py --member "${member}" 
