#!/bin/bash

module load podman >/dev/null 2>&1

make my_alpine.stamp || exit 1

export HOST_VAR="foo"
export TOGGLE_VAR="set from OUTSIDE"
unset RANDOM_VAR

echo -e "\nStep #1:"
podman \
    --log-level error \
    run \
    my_alpine:latest /opt/container/speak.sh

echo -e "\nStep #2:"
podman \
    --log-level error \
    run \
    --env HOST_VAR \
    my_alpine:latest /opt/container/speak.sh

echo -e "\nStep #3:"
podman \
    --log-level error \
    run \
    --env TOGGLE_VAR="${TOGGLE_VAR}" \
    my_alpine:latest /opt/container/speak.sh

echo -e "\nStep #4:"
podman \
    --log-level error \
    run \
    --env RANDOM_VAR="set on command-line" \
    my_alpine:latest /opt/container/speak.sh
