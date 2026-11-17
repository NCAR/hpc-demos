# Sourced by launch_cf on the compute node before any step runs: the steps
# need NumPy and Numba.  A dated NCAR Python Library environment keeps the
# Numba version, and so the results, the same from run to run.
module load conda
conda activate npl-2026a

# NumPy's own math library does none of this program's work: keep it from
# starting a thread per core in every step
export OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
