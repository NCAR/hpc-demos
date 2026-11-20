# Sourced by launch_cf on the compute node before any step runs: the steps
# need h5py, NumPy and Numba.  A dated NCAR Python Library environment keeps
# the versions, and so the results, the same from run to run.
module load conda
conda activate npl-2026a

# Numba's default threading layer here is TBB, which hands loop chunks to
# threads dynamically and so defeats first-touch placement; use OpenMP's.
export NUMBA_THREADING_LAYER=omp

# NumPy's own math library does none of this program's work: keep it from
# starting a thread per core in every step
export OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
