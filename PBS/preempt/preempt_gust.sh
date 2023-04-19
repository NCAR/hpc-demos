#!/bin/bash
#PBS -N hello_preempt
#PBS -A <project_code>
#PBS -j oe
#PBS -q preempt
#PBS -l walltime=00:30:00
#PBS -l select=8:ncpus=128:mpiprocs=32:ompthreads=4:mem=250G

### Set temp to scratch
export TMPDIR=/glade/gust/scratch/${USER}/temp && mkdir -p $TMPDIR

module list
make clean && make all

while true; do
    echo && echo && echo "Running the C code..."
    ./cdemo

    echo && echo && echo "Running the Fortran code..."
    ./fdemo

    echo && echo && echo "Running the Bash script..."
    ./demo.sh

    echo && echo && echo "Running the Python code..."
    ./demo.py
done

echo && echo && echo "Done at $(date)"
