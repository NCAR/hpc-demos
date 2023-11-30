#!/bin/bash

module load apptainer >/dev/null 2>&1

podman run rockylinux/rockylinux:9 cat /etc/os-release
