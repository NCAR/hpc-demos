#!/bin/bash
#
# Compare the pinned and unpinned runs by their STEP times.
#
# Each step's log (stdout-<job id>/step-*.out) ends with a line from
# process_file.sh giving how long that step took.  Those are the numbers to
# compare: the time the whole array took also counts the minutes its array jobs
# spent waiting for a node.
#
# A partly filled last node runs its few steps much faster than a full node
# runs its 42 -- they do not contend for the filesystem -- so only steps on full
# nodes go into the statistics.  The rest are counted but left out.
#
# Usage: ./compare_runs.sh [launch_cf log or stdout dir ...]
#          default: launch_cf.log launch_cf.pinned.log (as the submit scripts write)

set -u
[ $# -gt 0 ] || set -- launch_cf.log launch_cf.pinned.log

printf "%-24s %6s %6s %8s %8s %8s %8s\n" "run" "steps" "failed" "mean s" "median s" "max s" "omitted"
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

    # read each step's line by field name, then summarize the full-node steps
    cat "${dir}"/step-*.out 2>/dev/null | awk -F' [|] ' -v run="${run}" '
        /^step / {
            idx = 0; secs = ""; failed = 0
            for (i = 1; i <= NF; i++) {
                split($i, kv, /[ =]/)
                if (kv[1] == "seconds")         secs = kv[2]
                if (kv[1] == "failed")          failed = kv[2]
                if (kv[1] == "PBS_ARRAY_INDEX") idx = kv[2]
            }
            if (secs == "") next
            m++; on[m] = idx; t[m] = secs + 0; per[idx]++; bad += (failed > 0)
        }
        END {
            if (m == 0) { printf "%-24s no step results\n", run; exit }
            full = 0; for (i in per) if (per[i] > full) full = per[i]
            n = 0
            for (r = 1; r <= m; r++) {
                if (per[on[r]] != full) { omitted++; continue }
                # insertion sort, for the median
                v = t[r]; j = ++n
                while (j > 1 && s[j - 1] > v) { s[j] = s[j - 1]; j-- }
                s[j] = v; sum += v
            }
            med = (n % 2) ? s[(n + 1) / 2] : (s[n / 2] + s[n / 2 + 1]) / 2
            printf "%-24s %6d %6d %8.2f %8.2f %8.2f %8d\n", run, m, bad, sum / n, med, s[n], omitted
        }'
done
