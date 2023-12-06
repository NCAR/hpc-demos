#!/bin/bash

module load charliecloud >/dev/null 2>&1

make -s my_alpine.sqfs || exit 1
. config_demo_env_vars.sh || exit 1

echo -e "# Step #1:"
set -x
ch-run \
    ./my_alpine.sqfs -- /opt/container/speak.sh
set +x

echo -e "\n# Step #2:"
set -x
ch-run \
    --set-env=TOGGLE_VAR="${TOGGLE_VAR}" \
    ./my_alpine.sqfs -- /opt/container/speak.sh
set +x

echo -e "\n# Step #3:"
set -x
ch-run \
    --set-env=RANDOM_VAR="set_on_command-line" \
    ./my_alpine.sqfs -- /opt/container/speak.sh
set +x
