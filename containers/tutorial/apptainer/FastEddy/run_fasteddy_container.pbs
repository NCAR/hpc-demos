#!/bin/bash
#PBS -q main
#PBS -j oe
#PBS -o fasteddy_job.log
#PBS -l walltime=02:00:00
#PBS -l select=6:ncpus=64:mpiprocs=4:ngpus=4

module load ncarenv/23.09
module load apptainer gcc cuda || exit 1
module list

nnodes=$(cat ${PBS_NODEFILE} | sort | uniq | wc -l)
nranks=$(cat ${PBS_NODEFILE} | sort | wc -l)
nranks_per_node=$((${nranks} / ${nnodes}))

container_image="./rocky8-openhpc-fasteddy.sif"

singularity \
    --quiet \
    exec \
    ${container_image} \
    ldd /opt/local/FastEddy-model/SRC/FEMAIN/FastEddy

singularity \
    --quiet \
    exec \
    --bind ${SCRATCH} \
    --bind ${WORK} \
    --pwd $(pwd) \
    --bind /run \
    --bind /opt/cray \
    --bind /usr/lib64:/host/lib64 \
    --env LD_LIBRARY_PATH=${CRAY_MPICH_DIR}/lib-abi-mpich:/opt/cray/pe/lib64:${LD_LIBRARY_PATH}:/host/lib64 \
    --env LD_PRELOAD=/opt/cray/pe/mpich/${CRAY_MPICH_VERSION}/gtl/lib/libmpi_gtl_cuda.so.0 \
    ${container_image} \
    ldd /opt/local/FastEddy-model/SRC/FEMAIN/FastEddy



echo "# --> BEGIN execution"; tstart=$(date +%s)

mpiexec \
    --np ${nranks} --ppn ${nranks_per_node} --no-transfer \
    set_gpu_rank \
    singularity \
    --quiet \
    exec \
    --bind ${SCRATCH} \
    --bind ${WORK} \
    --pwd $(pwd) \
    --bind /run \
    --bind /opt/cray \
    --bind /usr/lib64:/host/lib64 \
    --env LD_LIBRARY_PATH=${CRAY_MPICH_DIR}/lib-abi-mpich:/opt/cray/pe/lib64:${LD_LIBRARY_PATH}:/host/lib64 \
    --env LD_PRELOAD=/opt/cray/pe/mpich/${CRAY_MPICH_VERSION}/gtl/lib/libmpi_gtl_cuda.so.0 \
    --env MPICH_GPU_SUPPORT_ENABLED=1 \
    --env MPICH_GPU_MANAGED_MEMORY_SUPPORT_ENABLED=1 \
    --env MPICH_SMP_SINGLE_COPY_MODE=NONE \
    ${container_image} \
    /opt/local/FastEddy-model/SRC/FEMAIN/FastEddy \
    ./Example02_CBL.in

echo "# --> END execution"
echo $(($(date +%s)-${tstart})) " elapsed seconds; $(date)"
