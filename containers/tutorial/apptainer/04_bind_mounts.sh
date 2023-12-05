#!/bin/bash

module load apptainer >/dev/null 2>&1

make my_alpine.sif || exit 1

echo -e "\nStep #1:"
singularity \
    --quiet \
    run \
    ./my_alpine.sif /opt/container/list_glade_filesystems.sh


echo -e "\nStep #2:"
singularity \
    --quiet \
    run \
    --bind ${HOME} \
    --bind ${SCRATCH} \
    --bind ${WORK} \
    --bind /glade/campaign \
    --bind "${WORK}:/random/path" \
    ./my_alpine.sif /opt/container/list_glade_filesystems.sh
