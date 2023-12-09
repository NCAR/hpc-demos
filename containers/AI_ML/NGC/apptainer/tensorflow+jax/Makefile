tensorflow+jax.sif: tensorflow+jax.def
	module load apptainer ; \
	export APPTAINER_TMPDIR=/var/tmp/ ; \
	export APPTAINER_CACHEDIR=${WORK}/.apptainer-cache/ ; \
	. $$PWD/config_env.sh && singularity build --nv $@ $<

# include common rules for all containers
include ../Make.common
