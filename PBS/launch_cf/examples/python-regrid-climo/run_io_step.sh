#!/usr/bin/bash
#
# One step: one ERA5 file through calc_anomaly_numba_io.py (h5py) or
# calc_anomaly_numba_pario.py (parallel decompression), or
# calc_anomaly_numba_climo.py (one pass, long-term climatology), timed by /usr/bin/time.
# "climoh5" runs calc_anomaly_numba_climo.py --h5py (one pass, h5py read).
# "keep" runs calc_anomaly_numba_pario.py --keep (decompress each chunk once).
# The thread count and any numactl placement come from the command file.
#
# Usage:  ./run_io_step.sh <climo|climoh5|io|pario|keep> <member> <ERA5 file> [more script arguments]

extra=()
case "$1" in
    keep) script="./calc_anomaly_numba_pario.py"; extra=(--keep) ;;
    climoh5) script="./calc_anomaly_numba_climo.py"; extra=(--h5py) ;;
    *)    script="./calc_anomaly_numba_$1.py" ;;
esac
member="$2"
file="$3"
shift 3

/usr/bin/time -f "Elapsed time: %E | Max RSS: %M KB | Major faults: %F | Swaps: %W | \
Waits (Voluntary context switches): %w | Involuntary context switches: %c" \
 "${script}" --member "${member}" --file "${file}" "${extra[@]}" "$@"
