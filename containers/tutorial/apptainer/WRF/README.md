# Demo containerized WRF

## Interacting with the container image
```
host$ make run-shell

Apptainer> cd /container/

Apptainer> ls
  WPS  WRF  config_env.sh  hdf5  mpich-3.4.3  netcdf  wps-4.3.1  wrf-4.4.2  wrf-chem-4.4.2

Apptainer> . config_env.sh

Apptainer> mpif90 --version
  GNU Fortran (SUSE Linux) 7.5.0
  Copyright (C) 2017 Free Software Foundation, Inc.
  This is free software; see the source for copying conditions.  There is NO
  warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

Apptainer> ls /container/w*-*/
  /container/wps-4.3.1/:
  avg_tsfc.exe	   compile-wps.log	  g1print.exe  height_ukmo.exe	mod_levs.exe
  build-env-wps.log  configure-wps-out.log  g2print.exe  int2nc.exe	rd_intermediate.exe
  calc_ecmwf_p.exe   configure.wps	  geogrid.exe  metgrid.exe	ungrib.exe

  /container/wrf-4.4.2/:
  build-env-wrf.log    configure-wrf-out.log  ndown.exe  tc.exe
  compile-wrf-out.log  configure.wrf	    real.exe   wrf.exe

  /container/wrf-chem-4.4.2/:
  build-env-wrfchem.log	 configure-wrfchem-out.log  ndown.exe  tc.exe
  compile-wrfchem-out.log  configure.wrf		    real.exe   wrf.exe

Apptainer> cd /container/WRF && git branch
  * local/v4.4.2
    master

Apptainer> cd /container/WPS && git branch
  * local/v4.3.1
    master

Apptainer> env | sort | grep -v SINGU
  APPTAINER_APPNAME=
  APPTAINER_BIND=/glade/u/home,/glade/work,/glade/campaign,/glade/derecho/scratch
  APPTAINER_COMMAND=shell
  APPTAINER_CONTAINER=/glade/u/home/benkirk/repos/csg-utils/hpc-demos/containers/tutorial/apptainer/WRF/ncar-derecho-wrf.sif
  APPTAINER_ENVIRONMENT=/.singularity.d/env/91-environment.sh
  APPTAINER_NAME=ncar-derecho-wrf.sif
  FLEX_LIB_DIR=/usr/lib64
  HDF5=/container/hdf5
  HDF5_VERSION=1.10.11
  HOME=/glade/u/home/benkirk
  JASPERINC=/usr/include
  JASPERLIB=/usr/lib64
  LANG=C
  LD_LIBRARY_PATH=/container/mpich-3.4.3/install/lib:/container/netcdf/lib:/container/hdf5/lib:/container/mpich-3.4.3/install/lib:/container/netcdf/lib:/container/hdf5/lib:/.singularity.d/libs
  LIB_LOCAL=-lnetcdf -lnetcdff -Wl,-rpath,/container/netcdf/lib/ -Wl,-rpath,/container/hdf5/lib/
  MPICH_VERSION=3.4.3
  NETCDF=/container/netcdf
  NETCDF_C_VERSION=4.9.2
  NETCDF_FORTRAN_VERSION=4.6.1
  OLDPWD=/container/WRF
  PATH=/container/mpich-3.4.3/install/bin:/container/netcdf/bin:/container/hdf5/bin:/container/mpich-3.4.3/install/bin:/container/netcdf/bin:/container/hdf5/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  PS1=Apptainer>
  PWD=/container/WPS
  SHELL=/bin/bash
  SHLVL=1
  TERM=xterm-256color
  WPS_VERSION=4.3.1
  WRF_VERSION=4.4.2
  YACC=/usr/bin/byacc -d
  _=/usr/bin/env

Apptainer> exit
```

## Running WRF from the container
```pre
# inspect run_wrf_container.sh, especially ${container_exe}
# as that is the executable to be laucnhed

host$ qsub -A <PBS_ACCOUNT> ./run_wrf_container.sh

host$ PBS_ACCOUNT=SCSG0001 make run
```
