#!/bin/bash
#PBS -N hello_pbs
#PBS -A SCSG0001
#PBS -j oe
##PBS -o pbsjob.log
#PBS -q casper
#PBS -l walltime=00:05:00
#PBS -l select=2:ncpus=4:mpiprocs=2:ompthreads=2:mem=8G:ngpus=2
#PBS -l gpu_type=a100

module --force purge
module load ncarenv/23.10
module reset
module load apptainer
module list

### Interrogate Environment
env | egrep "PBS|MPI|THREADS" | sort
nodes_list=$(cat $PBS_NODEFILE | sort | uniq)
nodes_list=${nodes_list//.ib0.cheyenne.ucar.edu/}
nodes_list=${nodes_list//.hpc.ucar.edu/}
echo "NODES=\""${nodes_list}"\""

nvidia-smi

### Run MPT MPI Program
mpicxx -o hello_world_casper /glade/u/home/benkirk/hello_world_mpi.C -fopenmp
mpiexec ./hello_world_casper

container_img="$(pwd)//libexec/cisldev-almalinux9-gcc13-openmpi-cuda.sif"

singularity \
    --quiet \
    exec \
    --nv \
    --bind /glade \
    --bind /local_scratch \
    ${container_img} \
    ldd "$(pwd)/inst/cisldev-almalinux9-gcc13-openmpi-cuda/osu-micro-benchmarks/7.5/libexec/osu-micro-benchmarks/mpi/collective/osu_alltoall"

for collective in osu_allreduce osu_alltoall; do

    container_exe="$(pwd)/inst/cisldev-almalinux9-gcc13-openmpi-cuda/osu-micro-benchmarks/7.5/libexec/osu-micro-benchmarks/mpi/collective/${collective}"
    echo "Running ${container_exe}"

    mpiexec \
        singularity \
        --quiet \
        exec \
        --nv \
        --bind /glade \
        --bind /local_scratch \
        ${container_img} \
        ${container_exe}

    nvidia-smi >/dev/null 2>&1 && \
        mpiexec \
            singularity \
            --quiet \
            exec \
            --nv \
            --bind /glade \
            --bind /local_scratch \
            ${container_img} \
            ${container_exe} -d managed
done

for pt2pt in osu_latency osu_bibw; do

    container_exe="$(pwd)/inst/cisldev-almalinux9-gcc13-openmpi-cuda/osu-micro-benchmarks/7.5/libexec/osu-micro-benchmarks/mpi/pt2pt/${pt2pt}"
    echo "Running ${container_exe}"

    mpiexec -n 2 \
            singularity \
            --quiet \
            exec \
            --nv \
            --bind /glade \
            --bind /local_scratch \
            ${container_img} \
            ${container_exe}

    nvidia-smi >/dev/null 2>&1 && \
        mpiexec -n 2 \
                singularity \
                --quiet \
                exec \
                --nv \
                --bind /glade \
                --bind /local_scratch \
                ${container_img} \
                ${container_exe} D D
done


echo && echo && echo "Done at $(date)"
