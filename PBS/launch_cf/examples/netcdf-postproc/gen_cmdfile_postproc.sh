#!/bin/bash
#
# Write a command file with one step per input NetCDF file.
#
# Each step runs ./process_file.sh, which runs several NCO operations over its
# file at the same time (see the comments there).
#
# Passing "pin" as the second argument prefixes every step with
#
#     taskset -c <lo>-<hi>
#
# which locks that step -- and therefore all of its concurrent NCO processes --
# onto its own block of ops_per_step (3) cores.  launch_cf hands out steps to
# nodes in blocks of "steps per node", so the blocks simply cycle 0-2, 3-5, ...,
# 123-125, 0-2, ... down the file.
#
# Generate both files, submit both, and compare the runs with ./compare_runs.sh,
# which summarizes each run's step times.  Don't compare how long the whole
# array took: its array jobs run one after another as nodes come free, so that
# measures the queue as much as the placement.
#
# Usage:  ./gen_cmdfile_postproc.sh            unpinned, writes ./cmdfile
#         ./gen_cmdfile_postproc.sh pin        pinned,   writes ./cmdfile.pinned
#         ./gen_cmdfile_postproc.sh pin <file> pinned,   writes <file>
#
#           These defaults are the files submit_launch_cf.sh and
#           submit_launch_cf_pinned.sh submit.  "pin" may come before or after
#           the file name.
#
#         LAT_RANGE=-90.,90. LON_RANGE=0.,359.75 ./gen_cmdfile_postproc.sh
#           a different region (here the whole globe); see below

#------------------------------------------------------------------
datadir="./data"             # where make_data.sh put the input files
cores_per_node=128           # cores on a Derecho compute node
ops_per_step=3               # concurrent operations process_file.sh starts
node_memory_gb=235           # usable memory on a Derecho compute node

# A step is not one process: it starts ${ops_per_step} at once.  So the number
# of steps a node can hold is cores / ops, not cores -- otherwise the node runs
# 3x more processes than it has cores, and 3x more memory than budgeted.
# Tell launch_cf the same thing when you submit:
#
#     launch_cf --nthreads ${ops_per_step} ...
#
# which makes it compute this same steps/node and request ompthreads to match.
steps_per_node=$(( cores_per_node / ops_per_step ))

# Each run writes to its own directory.  Both runs process the same inputs and
# name their outputs after them, so a shared directory would mean the two runs
# overwriting each other's files -- and if they happen to run at the same time,
# writing the same file at the same time.
outdir_unpinned="./out.unpinned"
outdir_pinned="./out.pinned"

# The region every step reduces its file to; the default is roughly the
# contiguous United States.  It is passed to process_file.sh on every line of
# the command file -- the job does not see this shell's environment -- so the
# job runs exactly the region measured below.
#
# A wider region makes the steps write more, and so run longer, but it also
# raises their memory: ncks holds the whole region of a variable at once (ncra
# holds only one record of it).  The measurement below shows both.
lat_range="${LAT_RANGE:-25.,50.}"
lon_range="${LON_RANGE:-235.,295.}"
#------------------------------------------------------------------

# "pin" is a keyword wherever it appears; any other argument is the output file
pin=""
output=""
for arg in "$@"; do
    if [ "${arg}" = "pin" ]; then
        pin="yes"
    elif [ -z "${output}" ]; then
        output="${arg}"
    else
        echo "ERROR: unexpected argument '${arg}'"
        echo "usage: ./gen_cmdfile_postproc.sh [pin] [output file]"
        exit 1
    fi
done

# with "pin", each step is confined to its own block of cores
outdir="${outdir_unpinned}"
if [ -n "${pin}" ]; then
    outdir="${outdir_pinned}"
    output="${output:-./cmdfile.pinned}"
else
    output="${output:-./cmdfile}"
fi

files=( ${datadir}/*.nc )
if [ ${#files[@]} -eq 0 ] || [ ! -r "${files[0]}" ]; then
    echo "ERROR: no input files in ${datadir}/ -- run ./make_data.sh first"
    exit 1
fi

# The memory check below runs NCO here, on the login node.  config_env.sh only
# loads it inside the job, so load it now if it isn't already.
command -v ncra >/dev/null || module load nco 2>/dev/null

#------------------------------------------------------------------
# Memory check.
#
# A step runs all ${ops_per_step} operations at once, and a node runs
# ${steps_per_node} steps at once, so the node needs
#
#     steps/node x (sum of the memory for each operation)
#
# Exceed that and the job does not fail politely -- it takes the node down.
#
# Measure every operation rather than assuming they are alike, because NCO
# operators differ enormously.  ncra streams the file a record at a time; ncks
# holds a whole variable's region, a few hundred MB for the default region but
# over a GB for the globe; ncwa loads the whole array and needs roughly 10x its
# uncompressed size.  Measuring only the cheapest would clear a job that then
# exhausts the node.
#
# Each operation's elapsed time is shown too.  It is measured on a quiet login
# node; on a full compute node, steps have run about 3x longer (10 s, against
# 3 s on a nearly empty one), since 42 of them share the node's I/O.
#
# The probe also catches an operation that fails outright -- a region that
# misses the grid, say -- which would otherwise fail in every step of the job.
#
# Refuse to write a command file that cannot fit or cannot run.  FORCE=1
# overrides.
step_kb=0
measured=""
if [ ! -x /usr/bin/time ]; then
    why="/usr/bin/time is not installed here"
elif ! command -v ncra >/dev/null; then
    why="NCO is not loaded -- module load nco"
else
    probe="${files[0]}"
    echo "Measuring each operation on ${probe}"
    echo "  region: latitude ${lat_range}, longitude ${lon_range}"
    tmp=$(mktemp -d)
    region="-d latitude,${lat_range} -d longitude,${lon_range}"
    step_secs=0
    for op in "ncra -O ${region}" \
              "ncra -O -y max ${region}" \
              "ncks -O ${region}"; do
        if ! /usr/bin/time -f "%M %e" -o "${tmp}/kb" ${op} "${probe}" "${tmp}/probe.nc" \
                 >"${tmp}/err" 2>&1; then
            echo
            echo "ERROR: this operation fails on ${probe}:"
            echo "    ${op}"
            sed 's/^/    /' "${tmp}/err"
            [ -n "${FORCE:-}" ] || { rm -rf "${tmp}"; exit 1; }
            continue
        fi
        read -r kb secs < <(tail -1 "${tmp}/kb")
        case "${kb}" in ''|*[!0-9]*) continue ;; esac
        printf "  %-42s %6.2f GB %7.1f s\n" "${op}" "$(awk "BEGIN{print ${kb}/1048576}")" "${secs}"
        step_kb=$(( step_kb + kb ))
        # the ops run concurrently, so a step takes as long as its slowest
        step_secs=$(awk -v a="${step_secs}" -v b="${secs}" 'BEGIN {print (b > a) ? b : a}')
        measured="yes"
    done
    rm -rf "${tmp}"
    why="no operation could be measured"
fi

if [ -n "${measured}" ]; then
    step_gb=$(awk "BEGIN {printf \"%.2f\", ${step_kb}/1048576}")
    total_gb=$(awk "BEGIN {printf \"%.0f\", ${step_kb}*${steps_per_node}/1048576}")
    echo "  ---------------------------------"
    echo "  one step (${ops_per_step} concurrent ops): ${step_gb} GB, ~${step_secs} s here (expect ~3x on a full node)"
    echo "  ${steps_per_node} steps/node -> ${total_gb} GB; node has ${cores_per_node} cores and ${node_memory_gb} GB"
    if [ "${total_gb}" -gt "${node_memory_gb}" ] && [ -z "${FORCE:-}" ]; then
        cat <<MSG

REFUSING to write ${output}: a full node of these steps needs about ${total_gb} GB
but a node has ${node_memory_gb} GB.  The job would exhaust the node's memory.

Fewer input files will not help: launch_cf still puts ${steps_per_node} steps on
each node.  Instead narrow the region (LAT_RANGE, LON_RANGE), drop an operation
from process_file.sh, or put fewer steps on a node by raising
ops_per_step here and passing the same number to launch_cf --nthreads (which
leaves some of each step's cores idle).

Or set FORCE=1 if you know what you are doing.
MSG
        exit 1
    fi
else
    echo "warning: could not measure operation memory: ${why}."
    echo "         Check that steps/node x per-step memory fits in ${node_memory_gb} GB."
fi

# A partly filled last node costs a whole array job for a few steps.
left=$(( ${#files[@]} % steps_per_node ))
if [ ${left} -ne 0 ]; then
    down=$(( ${#files[@]} - left )) ; up=$(( down + steps_per_node ))
    alt="" ; [ ${down} -gt 0 ] && alt=" (or NFILES=${down})"
    echo "note: ${#files[@]} steps leave the last node running only ${left} of ${steps_per_node};"
    echo "      NFILES=${up}${alt} ./make_data.sh would fill every node."
fi

# Outputs left from an earlier run make the comparison and memory logs murky.
if [ -d "${outdir}" ] && [ -n "$(ls -A "${outdir}" 2>/dev/null)" ]; then
    echo "note: ${outdir}/ already holds output from an earlier run;"
    echo "      rm -rf ${outdir} before submitting for a clean comparison."
fi

{
    echo "# ${#files[@]} steps, one per NetCDF file in ${datadir}/"
    if [ -n "${pin}" ]; then
        echo "# Each step is pinned to its own ${ops_per_step} cores with taskset."
    else
        echo "# Steps are not pinned; the Linux scheduler places them."
    fi
    echo "#"
    echo "# Output goes to ${outdir}/"
    echo "# Region: latitude ${lat_range}, longitude ${lon_range}"
    echo "#"
    echo "# Each step starts ${ops_per_step} processes, so --nthreads ${ops_per_step} is what tells"
    echo "# launch_cf to put only ${steps_per_node} steps on a node instead of ${cores_per_node}."
    echo "#"
    echo "# Submit with:"
    echo "#   launch_cf -A \$PBS_ACCOUNT -l walltime=00:20:00 \\"
    echo "#             --nthreads ${ops_per_step} ${output}"
    echo "#"
    echo "# Generated by gen_cmdfile_postproc.sh"

    step=0
    for f in "${files[@]}"; do
        if [ -n "${pin}" ]; then
            # give the step the block of cores it is entitled to, not a single
            # core -- pinning 3 processes to 1 core would be a straw man
            slot=$(( step % steps_per_node ))
            lo=$(( slot * ops_per_step ))
            hi=$(( lo + ops_per_step - 1 ))
            echo "taskset -c ${lo}-${hi} ./process_file.sh ${f} ${outdir} ${lat_range} ${lon_range}"
        else
            echo "./process_file.sh ${f} ${outdir} ${lat_range} ${lon_range}"
        fi
        step=$(( step + 1 ))
    done
} > "${output}"

echo "Wrote ${#files[@]} steps to ${output}"
echo " -> output directory ${outdir}/"
echo " -> submit with --nthreads ${ops_per_step} (${steps_per_node} steps/node, $(( steps_per_node * ops_per_step )) processes on ${cores_per_node} cores)"
if [ -n "${pin}" ]; then
    echo " -> each step pinned to its own ${ops_per_step} cores with taskset"
else
    echo " -> steps unpinned, placed by the Linux scheduler"
fi
