#!/bin/bash
#PBS -N hello_pbs
#PBS -A SCSG0001
#PBS -j oe
##PBS -o pbsjob.log
#PBS -q main
#PBS -l walltime=00:05:00
#PBS -l select=2:ncpus=64:mpiprocs=4:ompthreads=4:ngpus=4

module --force purge
module load ncarenv/24.12
module reset
module load apptainer gcc cuda
module list

### Interrogate Environment
env | egrep "PBS|MPI|THREADS" | sort
nodes_list=$(cat $PBS_NODEFILE | sort | uniq)
nodes_list=${nodes_list//.ib0.cheyenne.ucar.edu/}
nodes_list=${nodes_list//.hpc.ucar.edu/}
echo "NODES=\""${nodes_list}"\""

nvidia-smi

### Run MPT MPI Program
mpicxx -o hello_world_derecho /glade/u/home/benkirk/hello_world_mpi.C -fopenmp
mpiexec ./hello_world_derecho

container_img="$(pwd)/libexec/cisldev-almalinux9-gcc-mpich-cuda.sif"

singularity \
    --quiet \
    exec \
    --nv \
    --bind /glade \
    --bind /local_scratch \
    ${container_img} \
    ldd "$(pwd)/inst/cisldev-almalinux9-gcc-mpich-cuda/osu-micro-benchmarks/7.5/libexec/osu-micro-benchmarks/mpi/collective/osu_alltoall"

singularity \
    --quiet \
    exec \
    --nv \
    --bind /glade \
    --bind /local_scratch \
    --bind /run --bind /var/run \
    --bind /opt/cray \
    --bind /usr/lib64:/host/lib64 \
    --env LD_LIBRARY_PATH=${CRAY_MPICH_DIR}/lib-abi-mpich:/opt/cray/pe/lib64:${LD_LIBRARY_PATH}:/host/lib64 \
    --env LD_PRELOAD=/opt/cray/pe/mpich/${CRAY_MPICH_VERSION}/gtl/lib/libmpi_gtl_cuda.so.0 \
    --env MPICH_SMP_SINGLE_COPY_MODE=NONE \
    ${container_img} \
    ldd "$(pwd)/inst/cisldev-almalinux9-gcc-mpich-cuda/osu-micro-benchmarks/7.5/libexec/osu-micro-benchmarks/mpi/collective/osu_alltoall"

for collective in osu_allreduce osu_alltoall; do

    container_exe="$(pwd)/inst/cisldev-almalinux9-gcc-mpich-cuda/osu-micro-benchmarks/7.5/libexec/osu-micro-benchmarks/mpi/collective/${collective}"
    echo "Running ${container_exe}"

    mpiexec \
        set_gpu_rank \
        singularity \
        --quiet \
        exec \
        --nv \
        --bind /glade \
        --bind /local_scratch \
        --bind /run --bind /var/run \
        --bind /opt/cray \
        --bind /usr/lib64:/host/lib64 \
        --env LD_LIBRARY_PATH=${CRAY_MPICH_DIR}/lib-abi-mpich:/opt/cray/pe/lib64:${LD_LIBRARY_PATH}:/host/lib64 \
        --env LD_PRELOAD=/opt/cray/pe/mpich/${CRAY_MPICH_VERSION}/gtl/lib/libmpi_gtl_cuda.so.0 \
        --env MPICH_SMP_SINGLE_COPY_MODE=NONE \
        ${container_img} \
        ${container_exe}

    nvidia-smi >/dev/null 2>&1 && \
        mpiexec \
            set_gpu_rank \
            singularity \
            --quiet \
            exec \
            --nv \
            --bind /glade \
            --bind /local_scratch \
            --bind /run --bind /var/run \
            --bind /opt/cray \
            --bind /usr/lib64:/host/lib64 \
            --env LD_LIBRARY_PATH=${CRAY_MPICH_DIR}/lib-abi-mpich:/opt/cray/pe/lib64:${LD_LIBRARY_PATH}:/host/lib64 \
            --env LD_PRELOAD=/opt/cray/pe/mpich/${CRAY_MPICH_VERSION}/gtl/lib/libmpi_gtl_cuda.so.0 \
            --env MPICH_SMP_SINGLE_COPY_MODE=NONE \
            ${container_img} \
            ${container_exe} -d managed
done

for pt2pt in osu_latency osu_bibw; do

    container_exe="$(pwd)/inst/cisldev-almalinux9-gcc-mpich-cuda/osu-micro-benchmarks/7.5/libexec/osu-micro-benchmarks/mpi/pt2pt/${pt2pt}"
    echo "Running ${container_exe}"

    mpiexec -n 2 -ppn 2 \
            set_gpu_rank \
            singularity \
            --quiet \
            exec \
            --nv \
            --bind /glade \
            --bind /local_scratch \
            --bind /run --bind /var/run \
            --bind /opt/cray \
            --bind /usr/lib64:/host/lib64 \
            --env LD_LIBRARY_PATH=${CRAY_MPICH_DIR}/lib-abi-mpich:/opt/cray/pe/lib64:${LD_LIBRARY_PATH}:/host/lib64 \
            --env LD_PRELOAD=/opt/cray/pe/mpich/${CRAY_MPICH_VERSION}/gtl/lib/libmpi_gtl_cuda.so.0 \
            --env MPICH_SMP_SINGLE_COPY_MODE=NONE \
            ${container_img} \
            ${container_exe}

    nvidia-smi >/dev/null 2>&1 && \
        mpiexec -n 2 -ppn 2 \
                set_gpu_rank \
                singularity \
                --quiet \
                exec \
                --nv \
                --bind /glade \
                --bind /local_scratch \
                --bind /run --bind /var/run \
                --bind /opt/cray \
                --bind /usr/lib64:/host/lib64 \
                --env LD_LIBRARY_PATH=${CRAY_MPICH_DIR}/lib-abi-mpich:/opt/cray/pe/lib64:${LD_LIBRARY_PATH}:/host/lib64 \
                --env LD_PRELOAD=/opt/cray/pe/mpich/${CRAY_MPICH_VERSION}/gtl/lib/libmpi_gtl_cuda.so.0 \
                --env MPICH_SMP_SINGLE_COPY_MODE=NONE \
                ${container_img} \
                ${container_exe} D D
done


echo && echo && echo "Done at $(date)"
