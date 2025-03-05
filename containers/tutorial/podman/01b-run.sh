#!/bin/bash

module load podman >/dev/null 2>&1

podman run rockylinux/rockylinux:9 cat /etc/os-release
