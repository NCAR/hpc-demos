# Sourced by launch_cf on the compute node before any step runs.
#
# Every step calls ncks, so the NCO module has to be loaded there -- the
# modules you have loaded when you submit are not carried into the job.
# This file applies to every step of every run launched from this directory,
# which is exactly what you want for a module load.

module load nco

# Uncomment to record every operation's peak memory under <outdir>/mem/.
# This file is sourced ON THE COMPUTE NODE, which is why setting MEASURE in your
# login shell before submitting would have no effect.
#export MEASURE=1

# Uncomment to sample, every N seconds, which core each step's NCO processes run
# on and which cores they are allowed -- a direct check that taskset pinned them.
# See WATCH_CORES in process_file.sh.
#export WATCH_CORES=1
