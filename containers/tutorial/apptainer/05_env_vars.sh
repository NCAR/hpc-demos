#!/bin/bash

module load apptainer >/dev/null 2>&1

make my_alpine.sif || exit 1
. config_demo_env_vars.sh || exit 1

echo -e "\n# Step #1:"
set -x
singularity \
    --quiet \
    run \
    ./my_alpine.sif /opt/container/speak.sh
set +x

echo -e "\n# Step #2:"
set -x
singularity \
    --quiet \
    run \
    --cleanenv \
    ./my_alpine.sif /opt/container/speak.sh
set +x

echo -e "\n# Step #3:"
set -x
singularity \
    --quiet \
    run \
    --cleanenv \
    --env TOGGLE_VAR="${TOGGLE_VAR}" \
    ./my_alpine.sif /opt/container/speak.sh
set +x

echo -e "\n# Step #4:"
set -x
singularity \
    --quiet \
    run \
    --cleanenv \
    --env RANDOM_VAR="set_on_command-line" \
    ./my_alpine.sif /opt/container/speak.sh
set +x
