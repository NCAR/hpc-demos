# Sourced by launch_cf on the compute node before any step runs: the steps
# need NumPy and Numba.  A dated NCAR Python Library environment keeps the
# Numba version, and so the results, the same from run to run.
module load conda
conda activate npl-2026a
