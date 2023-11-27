#!/bin/bash

module load charliecloud >/dev/null 2>&1

ch-run ./rocky9.sqfs -- cat /etc/os-release
