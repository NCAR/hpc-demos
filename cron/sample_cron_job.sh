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

ssh derecho "hostname && uptime" 2>/dev/null || echo "Cannot ssh to Derecho."
ssh casper "hostname && uptime"  2>/dev/null || echo "Cannot ssh to Casper."

echo "My Casper Jobs:"
qstat -a casper@casper-pbs || echo "cannot connect to Casper PBS"

#echo "Casper node status:"
#pbsnodes -aSj -s casper-pbs || echo "cannot connect to Casper PBS"

echo "My Derecho Jobs:"
qstat -a main@desched1 || echo "cannot connect to Derecho PBS"

#echo "Derecho node status:"
#pbsnodes -aSj -s desched1 || echo "cannot connect to Derecho PBS"

#--------------------------------------------------------------
# go to desired directory, exit on failure:
cd /glade/work/${USER}/ || exit 1
