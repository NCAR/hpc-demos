#!/bin/bash

module load podman >/dev/null 2>&1

podman build --tag my_rocky9_xpdf:latest .
