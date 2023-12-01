#!/bin/bash

module load charliecloud >/dev/null 2>&1

ch-image build --force fakeroot --tag my_rocky9 .
