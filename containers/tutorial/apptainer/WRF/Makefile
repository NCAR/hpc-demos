container_image ?= centos7-wrf.sif

run: run_wrf_container.sh $(container_image) check-env
	rm -rf ./output
	mkdir -p ./output
	qsub -A $${PBS_ACCOUNT} $<

check-env:
ifndef PBS_ACCOUNT
	$(error PBS_ACCOUNT is undefined, try PBS_ACCOUNT=<my_account> $(MAKE) $(MAKECMDGOALS))
endif

clean:
	rm -f *~

pristine:
	git clean -xdf -e "*.sif"

%.sif:
	module load apptainer ; \
        TMPDIR=/var/tmp/$${USER}-singularity ; \
        mkdir -p $${TMPDIR} ; \
        singularity pull $@ docker://benjaminkirk/$(patsubst %.sif,%,$@):latest


run-shell: $(container_image)
	module load apptainer ; \
	singularity \
	  --quiet \
	  shell \
	  --cleanenv \
	  --writable-tmpfs \
	  --pwd $$(pwd) \
	  --bind /glade/u/home \
	  --bind /glade/work \
	  --bind /glade/campaign \
	  --bind /glade/derecho/scratch \
	  ./$<
