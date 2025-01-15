#!/bin/bash

#----------------------------------------------------------------------------
# environment
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
selfdir="$(dirname $(readlink -f ${BASH_SOURCE[0]}))"
#----------------------------------------------------------------------------

topdir="$(pwd)"

cd ${selfdir} || exit 1

type module >/dev/null 2>&1 || . /etc/profile.d/z00_modules.sh
module load ncarenv/24.12 >/dev/null 2>&1
module reset >/dev/null 2>&1
module load apptainer || exit 1

case "${0}" in
    *)
        container_img="$(basename ${0})"
        ;;
esac

make ${container_img}.sif >/dev/null || exit 1

cd ${topdir} || exit 1

unset extra_binds

[ -d /local_scratch ] && extra_binds="-B /local_scratch ${extra_binds}"

workdir="$(mktemp -d)"
mkdir -p ${workdir}/{tmp,var/tmp}
remove_workdir() { [ -d ${workdir} ] && echo "removing ${workdir}" && rm -rf "${workdir}"; }

trap remove_workdir EXIT

singularity \
    --quiet \
    run \
    --nv \
    --cleanenv \
    --bind /glade ${extra_binds} \
    --bind ${workdir}/tmp:/tmp \
    --bind ${workdir}/var/tmp:/var/tmp \
    ${selfdir}/${container_img}.sif

remove_workdir
