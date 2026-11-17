#!/bin/bash
#
# Shows how launch_cf --nodes spreads the 32 steps of cmdfile.short over
# different numbers of nodes.  --dryrun writes each job script (to ./dryrun/)
# but submits nothing, so this costs nothing.

export PATH=/glade/derecho/scratch/kedziora/pbstools/bin:$PATH
mkdir -p dryrun

for n in 1 2 3 5 40; do
    echo "=== --nodes ${n}"
    launch_cf -q develop -l walltime=0:05:00 -A ${PBS_ACCOUNT} --nthreads 8 \
        --nodes ${n} --script dryrun/nodes${n}.pbs --dryrun ./cmdfile.short \
        | grep -E '^ -> (steps_per_node|steps_at_once|waves_per_node)|^Running|^NOTE|^#PBS -(l select|J)'
    echo
done
