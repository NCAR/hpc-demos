#!/bin/bash
#
# Compare the pinned and unpinned runs, step by step.
#
# Each step's log (stdout-<job id>/step-*.out) ends with climatology.py's
# report line.  For each run this prints:
#
#   steps    steps with a report; "failed" counts steps without one
#   GB/s     each step's own throughput: mean over steps, then min and max
#   comp s   each step's compute time, mean over steps
#   node s   the compute time of each node's slowest step, mean over nodes.
#            A node is busy until its slowest step finishes, so this is what
#            placement costs a launch_cf job
#   local    share of thread time on the domain holding the thread's data
#   load s   time to read the file from GLADE, mean over steps; not part of
#            the other columns
#
# Every step of a run reads a different month, and months differ in length by
# up to 10%, so compare GB/s for speed.  The two runs read the same months, so
# their times can be compared with each other.
#
# Usage: ./compare_runs.sh [launch_cf log or stdout dir ...]
#          default: launch_cf.log launch_cf.pinned.log (as the submit scripts write)

set -u
[ $# -gt 0 ] || set -- launch_cf.log launch_cf.pinned.log

printf "%-22s %5s %6s %6s %6s %6s %7s %7s %6s %7s\n" \
    "run" "steps" "failed" "GB/s" "min" "max" "comp s" "node s" "local" "load s"
for run in "$@"; do
    if [ -d "${run}" ]; then
        dir="${run}"
    elif [ -r "${run}" ]; then
        # qsub prints the job id, e.g. 7672405[].desched1; the logs directory
        # is named after it without the "[]"
        id=$(grep -Eo '^[0-9]+(\[\])?\.[A-Za-z0-9.-]+' "${run}" | tail -1)
        [ -n "${id}" ] || { echo "${run}: no job id found"; continue; }
        dir="stdout-${id/\[\]/}"
    else
        echo "${run}: not found"; continue
    fi
    [ -d "${dir}" ] || { echo "${run}: no ${dir}/ (has the job run?)"; continue; }

    # the report line of each step, read by field name
    for f in "${dir}"/step-*.out; do
        line=$(grep 'GBps=' "${f}" | tail -1)
        echo "${line:-FAILED}"
    done | awk -v run="${run}" '
        $1 == "FAILED" { bad++; next }
        {
            delete f
            for (i = 1; i <= NF; i++) { split($i, kv, "="); f[kv[1]] = kv[2] }
            n++; g = f["GBps"] + 0; s = f["seconds"] + 0
            gsum += g; ssum += s; lsum += f["load_s"]
            if (n == 1 || g < lo) lo = g
            if (n == 1 || g > hi) hi = g
            if (f["local"] != "?") { loc += f["local"]; nloc++ }
            if (s > slowest[f["index"]]) slowest[f["index"]] = s
        }
        END {
            if (n == 0) { printf "%-22s no step results (%d failed)\n", run, bad; exit }
            for (k in slowest) { nodes++; nsum += slowest[k] }
            printf "%-22s %5d %6d %6.1f %6.1f %6.1f %7.1f %7.1f %5s %7.1f\n",
                run, n, bad, gsum / n, lo, hi, ssum / n, nsum / nodes,
                (nloc ? sprintf("%.0f%%", loc / nloc) : "?"), lsum / n
        }'
done
