run: run_fasteddy_container.pbs rocky8-openhpc-fasteddy.sif Example02_CBL.in check-env
	rm -rf ./output
	mkdir -p ./output
	qsub -A $${PBS_ACCOUNT} $<

check-env:
ifndef PBS_ACCOUNT
	$(error PBS_ACCOUNT is undefined, try PBS_ACCOUNT=<my_account> $(MAKE) $(MAKECMDGOALS))
endif

%.sif:
	module load apptainer ; \
        TMPDIR=/var/tmp/$${USER}-singularity ; \
        mkdir -p $${TMPDIR} ; \
        singularity pull $@ docker://benjaminkirk/$(patsubst %.sif,%,$@):latest

Example02_CBL.in: Makefile
	rm -f $@{,.tmp}
	wget https://raw.githubusercontent.com/NCAR/FastEddy-tutorials/main/examples/Example02_CBL.in -O $@.tmp
	sed -i 's/numProcsX = 4/numProcsX = 24/' $@.tmp
	sed -i 's/ioOutputMode = 0/ioOutputMode = 1/' $@.tmp
	mv $@{.tmp,}

fasteddy/$(NCAR_BUILD_ENV)/FastEddy: fasteddy/$(NCAR_BUILD_ENV)

fasteddy/$(NCAR_BUILD_ENV): Makefile
	rm -rf $@
	prefix=$$(pwd)/$@ ; \
	  mkdir -p $${prefix} ; \
	  cd $${prefix} ; \
	  git clone https://github.com/NCAR/FastEddy-model.git ; \
	  cd $${prefix}/FastEddy-model/SRC && fe_inc= && for d in */ */*/ ; do fe_inc="-I$$(pwd)/$${d} $${fe_inc}" ; done ; \
	  module list ; \
	  cd FEMAIN ; \
	  make \
	    TEST_CU_CC="nvcc -allow-unsupported-compiler" \
	    ARCH_CU_FLAGS="-arch=sm_80" \
	    TEST_LDFLAGS="-L$${CUDA_HOME}/targets/x86_64-linux/lib -lcurand -lcudart -lcuda -L$${NETCDF}/lib -lnetcdf" ; \
	mv ./FastEddy $${prefix}/ ; \
	cd $${prefix}/ ; \
	rm -rf $${prefix}/FastEddy-model ; \
	ldd $${prefix}/FastEddy
