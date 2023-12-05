#!/bin/bash

module load podman >/dev/null 2>&1

make -s my_alpine.stamp || exit 1
. config_demo_env_vars.sh || exit 1

echo -e "# Step #1:"
set -x
podman \
    --log-level error \
    run \
    my_alpine:latest /opt/container/speak.sh
set +x

echo -e "\n# Step #2:"
set -x
podman \
    --log-level error \
    run \
    --env HOST_VAR \
    my_alpine:latest /opt/container/speak.sh
set +x

echo -e "\n# Step #3:"
set -x
podman \
    --log-level error \
    run \
    --env TOGGLE_VAR="${TOGGLE_VAR}" \
    my_alpine:latest /opt/container/speak.sh
set +x

echo -e "\n# Step #4:"
set -x
podman \
    --log-level error \
    run \
    --env RANDOM_VAR="set_on_command-line" \
    my_alpine:latest /opt/container/speak.sh
set +x
