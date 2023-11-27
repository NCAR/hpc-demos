#!/bin/bash

module load apptainer >/dev/null 2>&1

singularity exec ./rocky9.sif cat /etc/os-release
