run: run_fasteddy_container.pbs rocky8-openhpc-fasteddy.sif Example02_CBL.in check-env
	mkdir ./output
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
