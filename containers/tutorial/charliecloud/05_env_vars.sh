#!/bin/bash

module load charliecloud >/dev/null 2>&1

make my_alpine.sqfs || exit 1

export HOST_VAR="foo"
export TOGGLE_VAR="set_from_OUTSIDE"
unset RANDOM_VAR

echo -e "\nStep #1:"
ch-run \
    ./my_alpine.sqfs -- /opt/container/speak.sh

echo -e "\nStep #2:"
ch-run \
    ./my_alpine.sqfs -- /opt/container/speak.sh

echo -e "\nStep #3:"
ch-run \
    --set-env=TOGGLE_VAR="${TOGGLE_VAR}" \
    ./my_alpine.sqfs -- /opt/container/speak.sh

echo -e "\nStep #4:"
ch-run \
    --set-env=RANDOM_VAR="set_on_command-line" \
    ./my_alpine.sqfs -- /opt/container/speak.sh
