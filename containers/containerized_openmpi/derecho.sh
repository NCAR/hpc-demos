#!/bin/bash -l

module load apptainer gcc/12
module list

set -x
container_img="opensuse15-openhpc-openmpi"

mpiexec -n 2 \
        singularity \
        --quiet \
        exec \
        --nv \
        -B /glade ${extra_binds}     \
        $(pwd)/${container_img}.sif \
        /container/osu-micro-benchmarks-7.2/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_bibw
