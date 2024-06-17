container_image ?= esmf_8_6_1.sif

all: $(container_image)

run-shell: $(container_image)
	@echo "Running interactive shell inside $<"
	module load apptainer ; \
	singularity \
	  --quiet \
	  shell \
	  --cleanenv \
	  --pwd $$(pwd) \
	  --bind /glade \
	  ./$<

# check-env:
# ifndef PBS_ACCOUNT
# 	$(error PBS_ACCOUNT is undefined, try PBS_ACCOUNT=<my_account> $(MAKE) $(MAKECMDGOALS))
# endif

clean:
	rm -f *~

pristine:
	git clean -xdf -e "*.sif"

$(container_image): Deffile
	@echo "Constructing $@ from $<"
	module load apptainer ; \
        export TMPDIR=/var/tmp/$${USER}-singularity/ ; \
	export APPTAINER_TMPDIR=/var/tmp/ ; \
        export APPTAINER_CACHEDIR=${WORK}/.apptainer-cache/ ; \
        mkdir -p $${TMPDIR} $${APPTAINER_TMPDIR} $${APPTAINER_CACHEDIR} ; \
        singularity build --force $@ $<
