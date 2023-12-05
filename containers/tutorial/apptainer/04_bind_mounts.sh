#!/bin/bash

module load apptainer >/dev/null 2>&1

make my_alpine.sif || exit 1

echo -e "\n# Step #1:"
set -x
singularity \
    --quiet \
    run \
    ./my_alpine.sif /opt/container/list_glade_filesystems.sh
set +x

echo -e "\n# Step #2:"
set -x
singularity \
    --quiet \
    run \
    --bind ${HOME} \
    --bind ${SCRATCH} \
    --bind ${WORK} \
    --bind /glade/campaign \
    --bind "${WORK}:/random/path" \
    ./my_alpine.sif /opt/container/list_glade_filesystems.sh
set +x
