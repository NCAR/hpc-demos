# Demo containerized WRF

## Interacting with the container image
```
host$ make run-shell

Apptainer> cd /container/

Apptainer> ls
WPS  WRF  config_env.sh  mpich-3.4.3  netcdf  wps-4.3.1  wrf-4.4.2  wrf-chem-4.4.2

Apptainer> . config_env.sh

Apptainer> mpicxx --version
   g++ (GCC) 8.5.0 20210514 (Red Hat 8.5.0-20)
   Copyright (C) 2018 Free Software Foundation, Inc.
   This is free software; see the source for copying conditions.  There is NO
   warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

Apptainer> ls /container/w*-*/
   /container/wps-4.3.1/:
   avg_tsfc.exe	   calc_ecmwf_p.exe	configure-wps-out.log  g1print.exe  geogrid.exe      int2nc.exe   mod_levs.exe	       ungrib.exe
   build-env-wps.log  compile-wps-out.log	configure.wps	       g2print.exe  height_ukmo.exe  metgrid.exe  rd_intermediate.exe

   /container/wrf-4.4.2/:
   build-env-wrf.log  compile-wrf-out.log	configure-wrf-out.log  configure.wrf  ndown.exe  real.exe  tc.exe  wrf.exe

   /container/wrf-chem-4.4.2/:
   build-env-wrfchem.log  compile-wrfchem-out.log	configure-wrfchem-out.log  configure.wrf  ndown.exe  real.exe  tc.exe  wrf.exe

Apptainer> cd /container/WRF

Apptainer> git branch
* local/v4.4.2
  master

Apptainer> cd ../WPS/

Apptainer> git branch
* local/v4.3.1
  master
Apptainer> env | sort | uniq | grep -v SING
   APPTAINER_APPNAME=
   APPTAINER_BIND=/glade/u/home,/glade/work,/glade/campaign,/glade/derecho/scratch
   APPTAINER_COMMAND=shell
   APPTAINER_CONTAINER=/glade/u/home/benkirk/repos/csg-utils/hpc-demos/containers/tutorial/apptainer/WRF/rocky8-wrf.sif
   APPTAINER_ENVIRONMENT=/.singularity.d/env/91-environment.sh
   APPTAINER_NAME=rocky8-wrf.sif
   FLEX_LIB_DIR=/usr/lib64
   HDF5=/usr
   HOME=/glade/u/home/benkirk
   JASPERINC=/usr/include
   JASPERLIB=/usr/lib64
   LANG=C
   LD_LIBRARY_PATH=/container/mpich-3.4.3/install/lib:/container/netcdf/lib:/.singularity.d/libs
   LIB_LOCAL=-lnetcdf -lnetcdff -Wl,-rpath,/container/netcdf/lib/
   MPICH_VERSION=3.4.3
   NETCDF=/container/netcdf
   NETCDF_C_VERSION=4.9.2
   NETCDF_FORTRAN_VERSION=4.6.1
   OLDPWD=/container/WRF
   PATH=/container/mpich-3.4.3/install/bin:/container/netcdf/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
   PS1=Apptainer>
   PWD=/container/WPS
   SHELL=/bin/bash
   SHLVL=1
   TERM=xterm-256color
   WPS_VERSION=4.3.1
   WRF_VERSION=4.4.2
   YACC=/usr/bin/yacc -d
   _=/usr/bin/env

Apptainer>
```

## Running WRF from the container
```pre
# inspect run_wrf_container.sh, especially ${container_exe}
# as that is the executable to be laucnhed

host$ qsub -A <PBS_ACCOUNT> ./run_wrf_container.sh

host$ PBS_ACCOUNT=SCSG0001 make run
```
