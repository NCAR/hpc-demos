#!/bin/bash
#
# Survey the ERA5 collection on GLADE and pick a product to run the example on.
#
# The only thing the example really needs from the data is FILE SIZE: every
# operation in process_file.sh streams, so memory is bounded whatever you pick,
# but file size sets how long a step runs.  ~475 MB files give steps of about
# 10 seconds on a full node, which is still short to measure placement against;
# bigger files give a cleaner signal.
#
# Sizes differ between the parameters of one product as much as between
# products (73 MB and 400+ MB files sit side by side in e5.oper.fc.sfc.meanflux),
# and make_data.sh stages a single parameter.  So this measures each PARAMETER,
# using every file in the product's first month, and recommends a product AND a
# parameter.
#
# Usage:
#   ./check_data.sh                 survey products and their file sizes
#   ./check_data.sh 500             also recommend a parameter of at least 500 MB
#   ./check_data.sh 500 d633000     a different dataset

set -u
target_mb="${1:-}"
dsid="${2:-d633000}"

echo "== 1. locating ${dsid} =========================================="
root=""
for candidate in /glade/campaign/collections/gdex/data /gdex/data \
                 /glade/campaign/collections/rda/data; do
    if [ -d "${candidate}/${dsid}" ]; then
        [ -z "${root}" ] && root="${candidate}"
        echo "   ${candidate}/${dsid}"
    fi
done
[ -n "${root}" ] || { echo "   NOT FOUND -- search ${dsid} at https://gdex.ucar.edu,"
                      echo "   then Data Access -> NCAR HPC Data Access"; exit 1; }
ds="${root}/${dsid}"

echo
echo "== 2. products and their file sizes ============================="

# The sizes are measured on disk because the gdexls catalogue is no help here:
# it describes the GRIB1 collection withdrawn from GLADE in 2025, and reports
# 0 files for the netCDF files that replaced it.
#
# One row per product and parameter:  <product> <param> <files> <avg MB>
table=$(mktemp)
for d in "${ds}"/*/; do
    [ -d "${d}" ] || continue
    p=$(basename "${d}")
    # the first month directory; a product without them is measured as it is
    month=$(find "${d}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -1)
    [ -n "${month}" ] || month="${d}"
    # products with no .nc (e.g. the Zarr stores) drop out
    find "${month}" -maxdepth 1 -name '*.nc' -type f -exec ls -l {} + 2>/dev/null \
        | awk -v p="${p}" '
            {
                f = $NF; sub(/.*\//, "", f)
                param = "-"
                if (match(f, /[0-9][0-9][0-9]_[0-9][0-9][0-9]_[A-Za-z0-9]+/))
                    param = substr(f, RSTART, RLENGTH)
                s[param] += $5; n[param]++
            }
            END { for (k in n) printf "%s %s %d %.1f\n", p, k, n[k], s[k]/n[k]/1048576 }' \
        >> "${table}"
done

[ -s "${table}" ] || { echo "   (no products found under ${ds})"; rm -f "${table}"; exit 1; }

printf "   %-34s %7s %12s %12s\n" "product" "params" "smallest" "largest"
printf "   %-34s %7s %12s %12s\n" "----------------------------------" "-------" "------------" "------------"
awk '
    { if (!($1 in n)) { order[++np] = $1; lo[$1] = $4; hi[$1] = $4 }
      n[$1]++
      if ($4 + 0 < lo[$1] + 0) lo[$1] = $4
      if ($4 + 0 > hi[$1] + 0) hi[$1] = $4 }
    END { for (i = 1; i <= np; i++) { p = order[i]; print p, n[p], lo[p], hi[p] } }' "${table}" \
    | sort -k4 -n | while read -r p np lo hi; do
        printf "   %-34s %7s %9s MB %9s MB\n" "${p}" "${np}" "${lo}" "${hi}"
    done
echo "   (average file size of each parameter, measured over the first month)"

echo
echo "== 3. recommendation ============================================"
prod="" ; param=""
if [ -z "${target_mb}" ]; then
    echo "   Re-run with a target file size in MB to get a suggestion, e.g."
    echo "     ./check_data.sh 500"
else
    # smallest parameter whose files are at least the target; the point of
    # asking for a size is to make steps run longer, so round up, not nearest
    best=$(awk -v t="${target_mb}" '
        $4+0 >= t+0 { if (p == "" || $4+0 < a+0) { p = $1; q = $2; a = $4 } }
        { if (mx == "" || $4+0 > mx+0) { mp = $1; mq = $2; mx = $4 } }
        END { if (p != "") print p, q, a, "atleast"; else print mp, mq, mx, "below" }' "${table}")
    set -- ${best}
    prod="${1}"; param="${2}"; size="${3}"
    if [ "${4}" = "atleast" ]; then
        echo "   at least ${target_mb} MB: ${prod}, parameter ${param} (~${size} MB per file)"
    else
        echo "   nothing reaches ${target_mb} MB; largest is ${prod}, parameter ${param} (~${size} MB per file)"
    fi
    echo
    if [ "${param}" = "-" ]; then
        param=""
        echo "   PRODUCT=${prod} ./make_data.sh"
    else
        echo "   PRODUCT=${prod} PARAM=${param} ./make_data.sh"
    fi
    echo
    echo "   all parameters of ${prod}:"
    awk -v p="${prod}" '$1 == p { printf "     %-20s %9s MB\n", $2, $4 }' "${table}" | sort -k2 -n
fi

# with no recommendation, check what make_data.sh stages by default -- or, for
# a dataset without that product, the first product surveyed
if [ -z "${prod}" ]; then
    prod="e5.oper.fc.sfc.meanflux"
    [ -d "${ds}/${prod}" ] || prod=$(head -1 "${table}" | cut -d' ' -f1)
fi
rm -f "${table}"

echo
echo "== 4. sanity check on one file =================================="
# The first file in sorted order -- the first make_data.sh would stage.  Look in
# the first month directory, which holds it, rather than sort the whole product.
month=$(find "${ds}/${prod}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -1)
sample=$(find "${month:-${ds}/${prod}}" -name "*${param}*.nc" 2>/dev/null | sort | head -1)
[ -n "${sample}" ] || sample=$(find "${ds}/${prod}" -name "*${param}*.nc" 2>/dev/null | sort | head -1)
if [ -z "${sample}" ]; then
    echo "   no .nc files found -- this dataset may live on object storage"
    exit 1
fi
echo "   ${sample}"
ls -lh "${sample}" | awk '{print "   readable, "$5}'
command -v ncdump >/dev/null || module load nco 2>/dev/null
if command -v ncdump >/dev/null; then
    ncdump -h "${sample}" | sed -n '/^dimensions:/,/^variables:/p' | grep "=" | sed 's/^/   /'
else
    echo "   (module load nco to see its dimensions)"
fi
