#!/bin/bash

module load podman >/dev/null 2>&1

podman image pull docker://rockylinux/rockylinux:9
podman images
podman save -o rocky9.tar rockylinux/rockylinux:9
