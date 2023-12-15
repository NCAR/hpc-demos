#!/bin/bash -l

#--------------------------------------------------------------
LOCK="${HOME}/.my_cron_job.lock"
remove_lock()
{
    rm -f "${LOCK}"
}

another_instance()
{
    echo "Cannot acquire lock on ${LOCK}"
    echo "There is another instance running, exiting"
    exit 1
}

# acquire an exclusive lock on our ${LOCK} file to make sure
# only one copy of this script is running at a time.
lockfile -r 5 -l 3600 "${LOCK}" || another_instance
trap remove_lock EXIT

#--------------------------------------------------------------
# logging:  Print status to standard out, and redirect also to our
# specified cron_logdir.
timestamp="$(date +%F@%H:%M)"
cron_logdir="${HOME}/.my_cron_logs/"
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
mkdir -p ${cron_logdir} || exit 1

echo -e "[${timestamp}]: Running ${0} on $(hostname)\n\tfrom $(pwd)\n\tscriptdir=${scriptdir}" \
    | tee -a ${cron_logdir}/sample_job.log

#--------------------------------------------------------------
echo "PATH=${PATH}"

#--------------------------------------------------------------
# go to desired directory, exit on failure:
cd /glade/work/${USER}/my_cron_job/ || { echo "cannot cd to the desired directory!!"; exit 1; }

# clean up any old INPUT_DATA
rm -f ./INPUT_DATA

# lauch preprocessing job, capturing its job ID
PREREQ=$(qsub -q casper@casper-pbs ./prep_job.pbs) || { echo "cannot connect to Casper PBS"; exit 1; }
echo ${PREREQ}

# lauch model job
qsub -q main@desched1 -W depend=afterok:${PREREQ} ./run_model.pbs || { echo "cannot connect to Derecho PBS"; exit 1; }
