# Makefile for the launch_cf examples.
#
#   make             build hello_omp.exe and generate the example command files
#   make cmdfiles    (re)generate the example command files only
#   make submit      submit the derecho-640procs example with launch_cf
#   make dryrun      show what that submission would request, without submitting
#   make csv         summarize a finished run into derecho-640procs/steps.csv
#   make clean       remove build products
#   make clobber     also remove job output from previous runs
#
# The compiler defaults to the Cray wrapper, which is what Derecho provides.
# Override on the command line if you need to, e.g.
#   make CXX=g++
#   make OMPFLAGS=-qopenmp     # Intel classic compilers

CXX      ?= CC
CXXFLAGS ?= -O2
OMPFLAGS ?= -fopenmp
PYTHON   ?= python3

launch_cf ?= launch_cf

# Each example directory holds its own cmdfile and submission script.
EXAMPLES := derecho-640procs thread-placement netcdf-postproc numa-python \
            numa-python-advanced

# Command files that can be generated with no further input.  netcdf-postproc
# is deliberately absent: its command files list the data files make_data.sh
# produced, so run "make netcdf-data" for that one.
CMDFILES := derecho-640procs/cmdfile \
            thread-placement/cmdfile \
            thread-placement/cmdfile.numactl \
            thread-placement/cmdfile.numactl_bind

all: hello_omp.exe $(CMDFILES)

hello_omp.exe: hello_omp.cpp
	$(CXX) $(CXXFLAGS) $(OMPFLAGS) -o $@ $<

cmdfiles: $(CMDFILES)

# 640 steps: with the Derecho defaults (128 CPUs, 1 thread per step) launch_cf
# runs 128 steps per node, so a 5-element job array.
derecho-640procs/cmdfile: gen_cmdfile.sh Makefile
	./gen_cmdfile.sh --nsteps 640 --exe ../hello_omp.exe --output $@

# 16 steps of a 16-thread program, run 8 per node, so a 2-element array.
# Three command files, the same except that the second binds each step to a
# NUMA domain, and the third also binds each thread to a core.
thread-placement/cmdfile: gen_cmdfile.sh Makefile
	./gen_cmdfile.sh --nsteps 16 --exe ../hello_omp.exe --output $@

thread-placement/cmdfile.numactl: gen_cmdfile_numactl.sh
	./gen_cmdfile_numactl.sh --nsteps 16 --nthreads 16 --output $@

# ...and the same again, additionally binding one thread per physical core.
thread-placement/cmdfile.numactl_bind: gen_cmdfile_numactl.sh
	./gen_cmdfile_numactl.sh --nsteps 16 --nthreads 16 --bind --output $@

# Build the NetCDF example's inputs, then both of its command files.  Slicing
# the source file takes a few minutes; see netcdf-postproc/make_data.sh for
# where the data comes from and how to point it elsewhere.
netcdf-data:
	cd netcdf-postproc && ./make_data.sh
	cd netcdf-postproc && ./gen_cmdfile_postproc.sh ./cmdfile
	cd netcdf-postproc && ./gen_cmdfile_postproc.sh ./cmdfile.pinned pin

# Both command files of the NUMA examples.  They list ERA5 files on GLADE, so
# they can only be generated on Derecho; see numa-python/gen_cmdfile_numa.sh.
numa-cmdfiles:
	cd numa-python && ./gen_cmdfile_numa.sh
	cd numa-python && ./gen_cmdfile_numa.sh bind

numa-advanced-cmdfiles:
	cd numa-python-advanced && ./gen_cmdfile_numa.sh
	cd numa-python-advanced && ./gen_cmdfile_numa.sh pin

submit: all
	cd derecho-640procs && ./submit_launch_cf.sh

# Same job, generated and described but not queued.  Requires launch_cf to be
# in your PATH, or override e.g. "make dryrun launch_cf=/path/to/launch_cf".
dryrun: all
	cd derecho-640procs && $(launch_cf) -A $${PBS_ACCOUNT} -l walltime=00:10:00 --dryrun ./cmdfile

# Collect the per-step output of the most recent run.  Override the run with
# "make csv RUNDIR=derecho-640procs/stdout-1234567"
RUNDIR ?= $(firstword $(shell ls -dt derecho-640procs/stdout-* 2>/dev/null))

csv:
	@test -n "$(RUNDIR)" || { echo "ERROR: no derecho-640procs/stdout-* directory found; run \"make submit\" first"; exit 1; }
	$(PYTHON) ./parse_steps.py $(RUNDIR) \
	  --lscpu derecho-640procs/lscpu.txt \
	  -o derecho-640procs/steps.csv

clean:
	rm -f hello_omp.exe *.o *~

clobber: clean
	rm -rf $(addsuffix /stdout-*,$(EXAMPLES))
	rm -f $(addsuffix /steps.csv,$(EXAMPLES))
	rm -f $(addsuffix /launch_cf.log,$(EXAMPLES))
	rm -f $(addsuffix /launch_cf.numactl.log,$(EXAMPLES))
	rm -f $(addsuffix /launch_cf.numactl_bind.log,$(EXAMPLES))
	rm -f $(addsuffix /launch_cf.pinned.log,$(EXAMPLES))
	rm -f $(addsuffix /launch_cf.bind.log,$(EXAMPLES))
	rm -rf netcdf-postproc/out.unpinned netcdf-postproc/out.pinned netcdf-postproc/out
	@echo "(netcdf-postproc/data left in place; delete it by hand to re-slice)"
	rm -f $(addsuffix /launch_cf.*.pbs,$(EXAMPLES))
	rm -f $(addsuffix /launch_cf.o*,$(EXAMPLES))

.PHONY: all cmdfiles netcdf-data numa-cmdfiles numa-advanced-cmdfiles submit dryrun csv clean clobber
