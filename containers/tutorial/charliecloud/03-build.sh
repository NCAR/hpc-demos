#!/bin/bash

module load charliecloud >/dev/null 2>&1

ch-image build --force fakeroot --tag my_rocky9 .
ch-image list
ch-convert my_rocky9 ./my_rocky9.sqfs
