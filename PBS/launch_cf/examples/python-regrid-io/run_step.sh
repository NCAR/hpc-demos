#!/usr/bin/bash

/usr/bin/time -f "Elapsed time: %E | Max RSS: %M KB | Major faults: %F | Swaps: %W | \
Waits (Voluntary context switches): %w | Involuntary context switche: %c" \
 ./calc_anomaly_numba_io.py 

