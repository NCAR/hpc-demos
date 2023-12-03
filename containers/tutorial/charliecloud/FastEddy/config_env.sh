module --force purge  >/dev/null 2>&1
module load ncarenv/23.10 >/dev/null 2>&1
module reset >/dev/null 2>&1
module load charliecloud apptainer gcc cuda ncarcompilers >/dev/null || exit 1
module avail
module list
