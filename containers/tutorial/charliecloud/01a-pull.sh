#!/bin/bash

module load charliecloud >/dev/null 2>&1

ch-image pull rockylinux/rockylinux:9
ch-image list
ch-convert rockylinux/rockylinux:9 ./rocky9.sqfs
ls -lh ./rocky9.sqfs
