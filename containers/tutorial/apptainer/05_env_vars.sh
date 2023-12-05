#!/bin/bash

module load apptainer >/dev/null 2>&1

make my_alpine.sif || exit 1

export HOST_VAR="foo"
export TOGGLE_VAR="set_from_OUTSIDE"
unset RANDOM_VAR

echo -e "\nStep #1:"
singularity --quiet run            ./my_alpine.sif /opt/container/speak.sh

echo -e "\nStep #2:"
singularity --quiet run --cleanenv ./my_alpine.sif /opt/container/speak.sh

echo -e "\nStep #3:"
singularity --quiet run --cleanenv --env TOGGLE_VAR="${TOGGLE_VAR}" ./my_alpine.sif /opt/container/speak.sh

echo -e "\nStep #4:"
singularity --quiet run --cleanenv --env RANDOM_VAR="set_on_command-line" ./my_alpine.sif /opt/container/speak.sh
