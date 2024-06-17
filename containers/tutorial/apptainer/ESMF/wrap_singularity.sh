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

container_img="esmf_8_6_1.sif"

make ${container_img} >/dev/null || exit 1

cd ${topdir} || exit 1

unset extra_binds

[ -d /local_scratch ] && extra_binds="-B /local_scratch ${extra_binds}"

singularity \
    --quiet \
    run \
    --cleanenv \
    -B /glade ${extra_binds} \
    ${selfdir}/${container_img}
