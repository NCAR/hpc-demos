container_image ?= cisldev-almalinux9-gcc-openmpi-cuda.sif

all: cisldev-almalinux9-gcc-openmpi-cuda.sif \
     cisldev-almalinux9-nvhpc-openmpi.sif \

run-shell: $(container_image)
	@echo "Running interactive shell inside $<"
	workdir="$$(mktemp -d)" ; \
	mkdir -p $${workdir}/{tmp,var/tmp} ; \
	module load apptainer ; \
	singularity \
	  --quiet \
	  shell \
	  --nv \
	  --cleanenv \
	  --pwd $$(pwd) \
	  --bind /glade \
	  --bind $${workdir}/tmp:/tmp \
	  --bind $${workdir}/var/tmp:/var/tmp \
	  ./$< ; \
	  rm -rf $${workdir}

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
	workdir="$$(mktemp -d)" ; \
	mkdir -p $${workdir}/{tmp,var/tmp} ; \
        singularity \
	  build \
          --bind $${workdir}/tmp:/tmp \
          --bind $${workdir}/var/tmp:/var/tmp \
	  --force \
	  $@ $< ; \
	rm -rf $${workdir}
	@ls -ltrh $@
	@ln -sf wrap_singularity.sh $*
