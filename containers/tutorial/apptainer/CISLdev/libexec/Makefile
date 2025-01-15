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

%.sif: %.def Makefile
	@echo "Constructing $@ from $<"
	module load apptainer ; \
	export TMPDIR=/var/tmp/$${USER}-singularity/ ; \
	export APPTAINER_TMPDIR=/var/tmp/ ; \
	export APPTAINER_CACHEDIR=${WORK}/.apptainer-cache/ ; \
	workdir="$$(mktemp -d)" ; \
	mkdir -p $${TMPDIR} $${APPTAINER_TMPDIR} $${APPTAINER_CACHEDIR} $${workdir}/{tmp,var/tmp} ; \
	singularity \
	  build \
	  --bind $${workdir}/tmp:/tmp \
	  --bind $${workdir}/var/tmp:/var/tmp \
	  --force \
	  $@ $< ; \
	rm -rf $${workdir}
	@ls -ltrh $@
	@cd ../bin/ && ln -sf ../libexec/wrap_singularity.sh $*
