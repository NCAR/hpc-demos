#!/bin/bash

module load apptainer >/dev/null 2>&1

singularity pull ./rocky9.sif docker://rockylinux/rockylinux:9
