#!/bin/sh

echo "------------------------------"
echo "HOST_VAR=${HOST_VAR}"
echo "CONTAINER_VAR=${CONTAINER_VAR}"
echo "TOGGLE_VAR=${TOGGLE_VAR}"
[ -z "${RANDOM_VAR}" ] || echo "RANDOM_VAR=${RANDOM_VAR}"
echo "------------------------------"
