#!/bin/bash

#----------------------------------------------------------------------------
# environment
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
selfdir="$(dirname $(readlink -f ${BASH_SOURCE[0]}))"
#----------------------------------------------------------------------------

topdir="$(pwd)"

cd ${selfdir} || exit 1

type module >/dev/null 2>&1 || . /etc/profile.d/z00_modules.sh
module load apptainer || exit 1

case "${0}" in
    *"gcc-dbg-mpich"*)
        container_img="ncar-derecho-wrf-dbg-gcc-mpich"
        ;;
    *"gcc-dbg-openmpi"*)
        container_img="ncar-derecho-wrf-dbg-gcc-openmpi"
        ;;
    *"gcc"*)
        container_img="ncar-derecho-wrf-gcc"
        ;;
    *"intel-dbg"*)
        container_img="ncar-derecho-wrf-dbg-intel"
        ;;
    *"intel"*)
        container_img="ncar-derecho-wrf-intel"
        ;;
    *"nvhpc"*)
        container_img="ncar-derecho-wrf-nvhpc"
        ;;
    *)
        echo "Huh??" ; exit 1
        ;;
esac


make ${container_img}.sif >/dev/null || exit 1

cd ${topdir} || exit 1

unset extra_binds

[ -d /local_scratch ] && extra_binds="-B /local_scratch ${extra_binds}"
#[ -d /glade/scratch ] && extra_binds="-B /glade/scratch ${extra_binds}"
#[ -d /glade/p ] && extra_binds="-B /glade/p ${extra_binds}"
#[ -d /glade/collections ] && extra_binds="-B /glade/collections ${extra_binds}"
#[ -d /glade/cheyenne/scratch ] && extra_binds="-B /glade/cheyenne/scratch ${extra_binds}"

singularity \
    --quiet \
    run \
    --cleanenv \
    -B /glade ${extra_binds} \
    ${selfdir}/${container_img}.sif
