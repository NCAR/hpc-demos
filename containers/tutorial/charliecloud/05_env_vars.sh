#!/bin/bash

module load charliecloud >/dev/null 2>&1

make my_alpine.sqfs || exit 1

export HOST_VAR="foo"
export TOGGLE_VAR="set from OUTSIDE"
unset RANDOM_VAR

echo -e "\nStep #1:"
ch-run ./my_alpine.sqfs -- /opt/container/speak.sh

#echo -e "\nStep #2:"
#singularity --quiet run --cleanenv ./my_alpine.sif /opt/container/speak.sh

#echo -e "\nStep #3:"
#singularity --quiet run --cleanenv --env "TOGGLE_VAR=\"${TOGGLE_VAR}\"" ./my_alpine.sif /opt/container/speak.sh

#echo -e "\nStep #4:"
#singularity --quiet run --cleanenv --env "RANDOM_VAR=\"set on command-line\"" ./my_alpine.sif /opt/container/speak.sh
