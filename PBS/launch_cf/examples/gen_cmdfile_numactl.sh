#!/bin/bash
#
# Write a launch_cf command file whose steps are each bound to NUMA domains
# with numactl.
#
# A Derecho CPU node has 128 cores in 8 NUMA domains of 16 cores:
#
#     domain 0 -> cores   0- 15        domain 4 -> cores  64- 79
#     domain 1 -> cores  16- 31        domain 5 -> cores  80- 95
#     domain 2 -> cores  32- 47        domain 6 -> cores  96-111
#     domain 3 -> cores  48- 63        domain 7 -> cores 112-127
#
# Each domain has its own memory, and a core reads its own domain's memory
# fastest.  Prefixing a step with
#
#     numactl --cpunodebind=3 --membind=3
#
# keeps the step's threads on domain 3's cores (--cpunodebind) and takes its
# memory from domain 3 (--membind).  Without the prefix, Linux may spread one
# step's threads over several domains, far from its memory.
#
# The number of threads per step sets how the steps share the domains:
#
#   threads  steps per domain  domains per step  steps per node
#   1-16     16 / threads      1                 8 x 16 / threads
#   32, 64   -                 threads / 16      128 / threads
#
# The thread count must divide 16, or be 32, 64 or 128.  Domains are handed
# out in order down the command file and then start over, so every block of
# (steps per node) consecutive lines fills one node's domains evenly.
# launch_cf gives each node such a block.
#
# numactl chooses the domain, but not the core each thread runs on inside it.
# --bind also puts
#
#     OMP_PROC_BIND=close OMP_PLACES=cores
#
# in front of each step, which gives every OpenMP thread its own core.

set -u

# Derecho CPU node.  Change these for another kind of node (see lscpu).
NUMA_DOMAINS=8
CORES_PER_DOMAIN=16

usage ()
{
    cat <<EOF
$(basename ${0}) <options>

   -n|--nsteps   #STEPS    number of steps (command file lines).  Default: 16
   -t|--nthreads #THREADS  threads per step.  Must divide ${CORES_PER_DOMAIN}, or be a
                           multiple of ${CORES_PER_DOMAIN} up to $(( NUMA_DOMAINS * CORES_PER_DOMAIN )).  Default: 16
   -e|--exe      COMMAND   command each step runs, given the step number as
                           its argument.  Default: "../hello_omp.exe"
   -b|--bind               also bind each OpenMP thread to its own core
   -o|--output   FILE      file to write.  Default: "./cmdfile.numactl"
   -h|--help               this message

Examples:

   # the thread-placement example: 16 steps of 16 threads, one per domain
   $(basename ${0}) --output thread-placement/cmdfile.numactl
   $(basename ${0}) --bind --output thread-placement/cmdfile.numactl_bind

   # 64 steps of 4 threads, 4 steps in each domain
   $(basename ${0}) --nsteps 64 --nthreads 4

   # 8 steps of 32 threads, each over 2 domains
   $(basename ${0}) --nsteps 8 --nthreads 32
EOF
}

nsteps=16
threads=16
exe="../hello_omp.exe"
bind=""
output="./cmdfile.numactl"

while [ ${#} -gt 0 ]; do
    case ${1} in
        "-n"|"--nsteps")    shift; nsteps="${1:-}";  shift ;;
        "-t"|"--nthreads")  shift; threads="${1:-}"; shift ;;
        "-e"|"--exe")       shift; exe="${1:-}";     shift ;;
        "-b"|"--bind")      bind="yes";              shift ;;
        "-o"|"--output")    shift; output="${1:-}";  shift ;;
        "-h"|"--help")      usage; exit 0 ;;
        *)
            echo "ERROR: unrecognized argument \"${1}\""
            echo
            usage
            exit 1
            ;;
    esac
done

for arg in nsteps threads; do
    case "${!arg}" in
        ''|*[!0-9]*|0) echo "ERROR: --${arg/threads/nthreads} must be a positive integer, got \"${!arg}\""; exit 1 ;;
    esac
done

cores_per_node=$(( NUMA_DOMAINS * CORES_PER_DOMAIN ))
if [ ${threads} -le ${CORES_PER_DOMAIN} ] && [ $(( CORES_PER_DOMAIN % threads )) -eq 0 ]; then
    domains_per_step=1
elif [ $(( threads % CORES_PER_DOMAIN )) -eq 0 ] && [ ${threads} -le ${cores_per_node} ] \
     && [ $(( NUMA_DOMAINS % (threads / CORES_PER_DOMAIN) )) -eq 0 ]; then
    domains_per_step=$(( threads / CORES_PER_DOMAIN ))
else
    echo "ERROR: --nthreads ${threads} doesn't fill whole NUMA domains of ${CORES_PER_DOMAIN} cores."
    echo "       Give a number that divides ${CORES_PER_DOMAIN}, or 32, 64 or 128."
    exit 1
fi
steps_per_node=$(( cores_per_node / threads ))
# the groups of domains a step can run on: 8 single domains, or 4 pairs, ...
ngroups=$(( NUMA_DOMAINS / domains_per_step ))

prefix=""
[ -n "${bind}" ] && prefix="OMP_PROC_BIND=close OMP_PLACES=cores "

tmp="${output}.tmp.$$"
trap 'rm -f "${tmp}"' EXIT

{
    echo "# launch_cf command file: ${nsteps} steps of \"${exe}\", ${threads} threads each,"
    if [ ${domains_per_step} -eq 1 ]; then
        per=$(( CORES_PER_DOMAIN / threads ))
        [ ${per} -eq 1 ] && per="one step" || per="${per} steps"
        echo "# bound to NUMA domains, ${per} per domain."
    else
        echo "# each bound to ${domains_per_step} NUMA domains."
    fi
    [ -n "${prefix}" ] && echo "# Each OpenMP thread is also bound to its own core."
    echo "#"
    echo "# Submit with ${steps_per_node} steps per node, so that every node's domains fill evenly:"
    echo "#   launch_cf -A \$PBS_ACCOUNT -l walltime=00:10:00 \\"
    echo "#             --nthreads ${threads} --steps-per-node ${steps_per_node} ${output}"
    echo "# To run more steps per node in waves, give --steps-per-node a multiple of"
    echo "# ${steps_per_node}, or --waves, and add --sync-waves."
    echo "#"
    echo "# Generated by gen_cmdfile_numactl.sh.  To write it again:"
    echo "#   gen_cmdfile_numactl.sh --nsteps ${nsteps} --nthreads ${threads} --exe \"${exe}\"${bind:+ --bind} --output \"${output}\""

    for step in $(seq 1 ${nsteps}); do
        group=$(( (step - 1) % ngroups ))
        first=$(( group * domains_per_step ))
        nodes="${first}"
        for (( d = first + 1; d < first + domains_per_step; d++ )); do
            nodes="${nodes},${d}"
        done
        echo "${prefix}numactl --cpunodebind=${nodes} --membind=${nodes} ${exe} ${step}"
    done
} > "${tmp}" || exit 1

mv "${tmp}" "${output}" || exit 1
trap - EXIT

echo "Wrote ${nsteps} steps to ${output}"
[ ${steps_per_node} -eq 1 ] && spn="1 step" || spn="${steps_per_node} steps"
echo " -> ${threads} threads per step, ${spn} per node:" \
     "launch_cf --nthreads ${threads} --steps-per-node ${steps_per_node}"
