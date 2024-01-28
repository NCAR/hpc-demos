#!/bin/bash -l
#PBS -q main
#PBS -j oe
#PBS -o wrf_container_job.log
#PBS -l walltime=02:00:00
#PBS -l select=2:ncpus=128:mpiprocs=4

module load ncarenv/23.09
module purge
module load apptainer gcc cray-mpich || exit 1
module list


if [ ! -z ${PBS_NODEFILE+x} ]; then
    nnodes=$(cat ${PBS_NODEFILE} | sort | uniq | wc -l)
    nranks=$(cat ${PBS_NODEFILE} | sort | wc -l)
    nranks_per_node=$((${nranks} / ${nnodes}))
fi

container_image="./rocky8-wrf.sif"
#container_image="./centos7-wrf.sif"
container_exe="/container/wrf-chem-4.4.2/wrf.exe"

# examine dynamic libraries before & after host MPI injection
echo -e "\nldd, container native:"
singularity \
    --quiet \
    exec \
    ${container_image} \
    ldd ${container_exe}

echo -e "\nldd, host MPI:"
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
    ${container_image} \
    ldd ${container_exe}

[ -z ${PBS_NODEFILE+x} ] && exit 0

  echo "# --> BEGIN execution"; tstart=$(date +%s)

mpiexec \
    --np ${nranks} --ppn ${nranks_per_node} --no-transfer \
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
    --env MPICH_SMP_SINGLE_COPY_MODE=NONE \
    ${container_image} \
    ${container_exe}

echo "# --> END execution"
echo $(($(date +%s)-${tstart})) " elapsed seconds; $(date)"
