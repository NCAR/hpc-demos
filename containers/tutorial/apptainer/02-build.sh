#!/bin/bash

module load apptainer >/dev/null 2>&1

TMPDIR=/var/tmp/ singularity build --fakeroot my_rocky9.sif Deffile
