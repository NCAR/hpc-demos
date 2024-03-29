container_image ?= ncar-derecho-wrf-gcc.sif

all: ncar-derecho-wrf-gcc.sif \
     ncar-derecho-wrf-intel.sif \
     ncar-derecho-wrf-nvhpc.sif

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

# '$*' matches the '%' part, see https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html
%.def: Deffile
	@echo "Constructing $@ from $<"
	@rm -f $@
	@cp $< $@.tmp
	@sed -i 's/<PLACEHOLDER_IMG_NAME>/$*/g' $@.tmp
	@mv $@{.tmp,}

%.sif: %.def
	@echo "Constructing $@ from $<"
	module load apptainer ; \
        export TMPDIR=/var/tmp/$${USER}-singularity/ ; \
	export APPTAINER_TMPDIR=/var/tmp/ ; \
        export APPTAINER_CACHEDIR=${WORK}/.apptainer-cache/ ; \
        mkdir -p $${TMPDIR} $${APPTAINER_TMPDIR} $${APPTAINER_CACHEDIR} ; \
        singularity build --force $@ $<
