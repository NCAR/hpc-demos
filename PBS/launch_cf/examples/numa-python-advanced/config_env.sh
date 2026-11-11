# Sourced by launch_cf on the compute node before any step runs.
#
# Every step runs python3 with NumPy and netCDF4, so the conda environment has
# to be activated there -- the environment you have when you submit is not
# carried into the job.  npl-2026a is the NCAR Python Library environment the
# results in README.md were measured with.

module load conda
conda activate npl-2026a
