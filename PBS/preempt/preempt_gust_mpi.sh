#!/bin/bash
#PBS -N hello_preempt
#PBS -A <project_code>
#PBS -j oe
#PBS -q preempt
#PBS -l walltime=01:00:00
#PBS -l select=2:ncpus=128:mpiprocs=32:ompthreads=4:mem=100G

### Set temp to scratch
export TMPDIR=/glade/gust/scratch/${USER}/temp && mkdir -p $TMPDIR

module list
[ -x ./minimal_mpi ] || make all

while true; do
    echo && echo && echo "Running the MPI code..."
    mpiexec -n 64 --ppn 32 ./minimal_mpi
done

echo && echo && echo "Done at $(date)"
