#!/bin/bash

module load apptainer >/dev/null 2>&1

make -s my_alpine.sif || exit 1

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
    --pwd "/opt/container" \
    ./my_alpine.sif /opt/container/list_glade_filesystems.sh
set +x

echo -e "\n# Step #3:"
set -x
singularity \
    --quiet \
    run \
    --bind ${HOME} \
    --bind /glade/derecho/scratch \
    --bind /glade/work \
    --bind /glade/campaign \
    --bind "/glade/work:/random/path" \
    ./my_alpine.sif /opt/container/list_glade_filesystems.sh
set +x
