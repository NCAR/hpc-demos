#!/bin/bash
#
# Point the example at a set of ERA5 files.
#
# ERA5 lives on GLADE in the NSF NCAR Geoscience Data Exchange (GDEX, formerly
# the RDA) as dataset d633000.  It is already one file per variable per period,
# which is the shape a command file wants, so there is nothing to build: we just
# make symlinks.  Every operation in process_file.sh streams, so the archive
# files can be used whole.
#
# The files staged are all the SAME parameter across successive periods, so that
# gather.sh can join the results into one time series and one climatology.
# Mixing parameters would give you a meaningless average of unlike quantities.
#
# Run ./check_data.sh first; it locates the dataset, reports what is there, and
# suggests a PRODUCT and PARAM for a given file size.
#
#   ./make_data.sh                        # 126 files from the default product
#   NFILES=252 ./make_data.sh             # more steps
#   PRODUCT=e5.oper.an.sfc ./make_data.sh # a different ERA5 product
#   COPY=1 ./make_data.sh                 # real copies instead of symlinks
#   PARAM=235_033_msshf ./make_data.sh    # a particular ERA5 parameter
#   SRCDIR=/some/other/dir ./make_data.sh # somewhere else entirely
#   CLEAN=1 ./make_data.sh                # replace what an earlier run staged
#
# The default of 126 files fills exactly three nodes at 42 steps per node (see
# gen_cmdfile_postproc.sh); pick a multiple of 42 so no node runs half empty.
#
# Re-running with the same settings is harmless: files already staged are kept.
# But ${OUTDIR} must hold ONLY this selection -- gen_cmdfile_postproc.sh and
# gather.sh use every file in it -- so if it holds anything else (a different
# parameter or product, or more files than NFILES) this refuses to run until
# you set CLEAN=1, which removes those files first.

set -u

DSID="${DSID:-d633000}"
PRODUCT="${PRODUCT:-e5.oper.fc.sfc.meanflux}"
OUTDIR="${OUTDIR:-./data}"
NFILES="${NFILES:-126}"

if [ -z "${SRCDIR:-}" ]; then
    for root in /glade/campaign/collections/gdex/data /gdex/data \
                /glade/campaign/collections/rda/data; do
        if [ -d "${root}/${DSID}/${PRODUCT}" ]; then
            SRCDIR="${root}/${DSID}/${PRODUCT}"
            break
        fi
    done
fi
SRCDIR="${SRCDIR:-}"

if [ -z "${SRCDIR}" ] || [ ! -d "${SRCDIR}" ]; then
    cat <<MSG
ERROR: cannot find ${DSID}/${PRODUCT} on GLADE.

Run ./check_data.sh to see what is available, or search the dataset id at
https://gdex.ucar.edu and follow Data Access -> NCAR HPC Data Access.
Set SRCDIR to a directory of NetCDF files to use something else.
MSG
    exit 1
fi

# One parameter only.  ERA5 filenames carry it as <table>_<number>_<short name>,
# e.g. e5.oper.fc.sfc.meanflux.235_033_msshf.ll025sc.<dates>.nc
# Without PARAM, take the one in the first file in sorted order, so the choice
# is the same every time.  ./check_data.sh suggests a PARAM by file size.
if [ -z "${PARAM:-}" ]; then
    first=$(find "${SRCDIR}" -name '*.nc' 2>/dev/null | sort | head -1)
    PARAM=$(basename "${first}" | grep -o '[0-9]\{3\}_[0-9]\{3\}_[A-Za-z0-9]*' | head -1)
fi
if [ -z "${PARAM}" ]; then
    echo "WARNING: could not identify a parameter in the filenames;"
    echo "         staging whatever sorts first -- gather.sh may mix quantities."
fi

# the files to stage, in time order (the paths are <product>/<YYYYMM>/<file>)
wanted=$(find "${SRCDIR}" -name "*${PARAM:+${PARAM}}*.nc" | sort | head -n "${NFILES}")
[ -n "${wanted}" ] || { echo "ERROR: no .nc files found under ${SRCDIR}"; exit 1; }
nwanted=$(echo "${wanted}" | wc -l | tr -d ' ')

mkdir -p "${OUTDIR}"

# anything already in ${OUTDIR} that is not part of this selection
stale=$(comm -23 <(ls -1 "${OUTDIR}" | grep '\.nc$' | sort) \
                 <(echo "${wanted}" | xargs -n1 basename | sort))
if [ -n "${stale}" ]; then
    nstale=$(echo "${stale}" | wc -l | tr -d ' ')
    if [ -z "${CLEAN:-}" ]; then
        cat <<MSG
ERROR: ${OUTDIR} already holds ${nstale} file(s) that are not part of this selection,
e.g. $(echo "${stale}" | head -1)

The command file and gather.sh would use them too, mixing them into the results.
Re-run with CLEAN=1 to remove them, or set OUTDIR to stage somewhere else.
MSG
        exit 1
    fi
    echo "${stale}" | while read -r f; do rm -f "${OUTDIR}/${f}"; done
    echo "Removed ${nstale} file(s) from an earlier selection"
fi

echo "Staging ${nwanted} files from"
echo "  ${SRCDIR}"
[ -n "${PARAM}" ] && echo "  parameter ${PARAM}, successive periods"

echo "${wanted}" | while read -r f; do
    dest="${OUTDIR}/$(basename "${f}")"
    if [ ! -e "${dest}" ] && [ ! -L "${dest}" ]; then
        if [ -n "${COPY:-}" ]; then cp "${f}" "${dest}"; else ln -s "${f}" "${dest}"; fi
    fi
done

staged=$(ls -1 "${OUTDIR}" | grep -c '\.nc$')
echo "Staged ${staged} files ($([ -n "${COPY:-}" ] && echo copies || echo symlinks))"
[ "${staged}" -lt "${NFILES}" ] && echo "  (only ${staged} available; asked for ${NFILES})"
exit 0
