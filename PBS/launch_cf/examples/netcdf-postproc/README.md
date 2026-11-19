# NetCDF Post-Processing with `launch_cf`

This example reduces a run of ERA5 reanalysis files on GLADE to regional
diagnostics. Each input file is one step of a command file, and each step runs
three NCO operations at the same time. When every step has finished, a short
serial script joins the pieces into finished products.

It demonstrates three things:

- **A parallel phase followed by a gather.** Many independent per-file steps
  run under `launch_cf`, then one script runs once, afterwards, to join them.
  Most analysis of this kind has that shape.
- **Steps that start several processes.** A step here is three processes, not
  one, so a node holds `128 / 3 = 42` steps, which `launch_cf --nthreads 3`
  tells it.
- **Checking memory before submitting.** The command file generator measures
  every operation on a real input and refuses to write a command file whose
  steps would exhaust a node.

It was also meant to compare pinned and unpinned placement. It turned out not
to show a difference, and [What we found](#what-we-found) says why. For an example
where placement matters, see [`../thread-placement`](../thread-placement).

## What each step does

[`process_file.sh`](process_file.sh) runs these three operations over one
input file, cut to a latitude/longitude region (by default roughly the
contiguous United States):

| operation     | output              | what it is                               |
| ------------- | ------------------- | ---------------------------------------- |
| `ncra`        | `<file>.mean.nc`    | mean over the file's period              |
| `ncra -y max` | `<file>.max.nc`     | maximum over the file's period           |
| `ncks`        | `<file>.series.nc`  | the full time series, region only        |

ERA5 forecast products (`e5.oper.fc.*`) have two time dimensions,
`forecast_initial_time` and, inside each record, `forecast_hour`. `ncra`
reduces only the first, so the step finishes the mean and the maximum over
`forecast_hour` with `ncwa`. It also drops variables that averaging turns
into nonsense, such as the "mean" of `utc_date`. Analysis products
(`e5.oper.an.*`) skip both steps.

A step exits non-zero if any of its operations fails. Outputs get their final
names only once they are complete, so a failed step leaves nothing behind for
the gather to pick up by mistake.

[`gather.sh`](gather.sh) then produces:

| file                        | contents                                          |
| --------------------------- | ------------------------------------------------- |
| `regional_timeseries.nc`    | every step's time series, joined in time order    |
| `regional_period_means.nc`  | one mean per input file                           |
| `regional_climatology.nc`   | the mean over every time in the series            |
| `regional_maximum.nc`       | the maximum over every input file                 |

The climatology is computed from the full time series, not from the per-file
means. Half-month files hold from 26 to 32 forecasts, so averaging the
per-file means would give every file the same weight whatever its length.

## Files

| file                           | role                                                           |
| ------------------------------ | -------------------------------------------------------------- |
| `check_data.sh`                | survey the ERA5 products on GLADE, suggest a product and parameter |
| `make_data.sh`                 | symlink (or copy) one parameter's files into `./data`          |
| `gen_cmdfile_postproc.sh`      | measure memory and time, write `cmdfile` or `cmdfile.pinned`   |
| `process_file.sh`              | one step: three concurrent reductions of one file              |
| `config_env.sh`                | sourced on the compute node: loads NCO, optional monitoring    |
| `submit_launch_cf.sh`          | submit the unpinned run                                        |
| `submit_launch_cf_pinned.sh`   | submit the pinned run                                          |
| `gather.sh`                    | join a run's outputs into the finished products                |
| `compare_runs.sh`              | compare runs by their step times                               |
| `smt_test.sh`                  | standalone test of SMT and pinning on one compute node         |

## Running it

All of this runs from this directory on a Derecho login node, except the
steps themselves and `smt_test.sh`. The scripts load NCO themselves if it isn't
already loaded. The submit scripts use `$PBS_ACCOUNT`, so set it first.

### 1. Choose the data

```
./check_data.sh            # products, parameters and file sizes
./check_data.sh 500        # also suggest a parameter with files of at least 500 MB
```

The data is ERA5 (dataset `d633000`) in the NSF NCAR Geoscience Data Exchange
on GLADE. File sizes differ as much between the parameters of one product as
between products. In `e5.oper.fc.sfc.meanflux`, for example, the averages range
from 13 to 669 MB. So `check_data.sh` measures each parameter, and recommends
a product *and* a parameter. The `gdexls` catalogue was no help here, because it
still describes the GRIB1 files withdrawn in 2025.

### 2. Stage the inputs

```
./make_data.sh                                          # 126 files of the default product
PRODUCT=e5.oper.fc.sfc.minmax PARAM=228_226_mxtpr ./make_data.sh
NFILES=42 CLEAN=1 ./make_data.sh                        # replace an earlier selection
```

This symlinks successive periods of **one** parameter into `./data`, so the
gather joins a single quantity. The default of 126 files fills exactly three
nodes at 42 steps per node; a multiple of 42 keeps every node full.

`./data` must hold only the current selection, because the command file and
the gather use every file in it. If it holds anything else, `make_data.sh`
stops, and `CLEAN=1` removes those files first. Other settings are `COPY=1`
(copy instead of symlinking), `SRCDIR` and `OUTDIR`.

### 3. Write the command files

```
./gen_cmdfile_postproc.sh          # unpinned  -> ./cmdfile,        outputs in ./out.unpinned
./gen_cmdfile_postproc.sh pin      # pinned    -> ./cmdfile.pinned, outputs in ./out.pinned
LAT_RANGE=-90.,90. LON_RANGE=0.,359.75 ./gen_cmdfile_postproc.sh   # the whole globe
```

Before writing anything, the script runs each operation on the first input and
reports its peak memory and elapsed time:

```
  region: latitude 25.,50., longitude 235.,295.
  ncra -O -d latitude,25.,50. -d longitude,235.,295.   0.16 GB     2.7 s
  ncra -O -y max -d latitude,25.,50. -d longitude,235.,295.   0.17 GB     1.3 s
  ncks -O -d latitude,25.,50. -d longitude,235.,295.   0.19 GB     1.3 s
  ---------------------------------
  one step (3 concurrent ops): 0.52 GB, ~2.70 s here (expect ~3x on a full node)
  42 steps/node -> 22 GB; node has 128 cores and 235 GB
```

It refuses to write a command file if a full node of steps would need more
than the node's 235 GB, or if an operation fails on the input (`FORCE=1`
overrides). It also points out a partly filled last node, and output left in
the output directory from an earlier run. The region is written into every
line of the command file, so the job runs exactly the region that was measured.
Writing to `/dev/null` measures without replacing a command file:

```
LAT_RANGE=-90.,90. LON_RANGE=0.,359.75 ./gen_cmdfile_postproc.sh /dev/null
```

Pinned steps get `taskset -c <lo>-<hi>`, each its own block of three cores
(`0-2`, `3-5`, ..., `123-125`), which the step's three NCO processes inherit.

### 4. Submit, gather, compare

```
./submit_launch_cf.sh              # writes launch_cf.log
./submit_launch_cf_pinned.sh       # writes launch_cf.pinned.log

./gather.sh                        # ./out.unpinned (the default)
./gather.sh ./out.pinned
./compare_runs.sh                  # reads the job ids from both logs
```

`gather.sh` checks that every input in `./data` has all three outputs, and
stops with a list if any are missing (`grep -l ERROR stdout-*/step-*.out` finds
the failed steps). It ignores files in the output directory that didn't come
from the current inputs.

`compare_runs.sh` compares the runs by **step** time. Each step's log ends with
a line from `process_file.sh` that gives how long that step took. The time the
whole array took isn't a fair comparison, because array jobs often run one
after another as nodes come free. Steps on a partly filled last node run much
faster than steps on a full one, so they are counted but left out of the
statistics:

```
run                       steps failed   mean s median s    max s  omitted
launch_cf.log               126      0    18.53    18.58    19.55        0
launch_cf.pinned.log        126      0    18.56    18.90    19.61        0
```

## What we found

- For independent, single-threaded steps like these, placement is not worth
  managing. With the filesystem in the picture, the steps are I/O-bound and
  pinning changes nothing. Without it, pinning costs a few percent, and SMT
  adds about 6%.
- Pinning should matter when **threads within one process share data and
  memory**. Then where threads run relative to each other and to their memory
  (the node's NUMA domains) affects speed, and the scheduler doesn't account
  for it. That is the subject of
  [`../thread-placement`](../thread-placement), which uses `numactl` to bind
  each step to a NUMA domain.
- This example is a good starting point for real post-processing: a parallel
  phase and a gather, several operations per step, a memory check before
  submitting, failures that can't slip through, and step-level timing.
- To make steps last minutes rather than seconds, give each step more files,
  for example one year (24 half-month files) per step. `ncra` and `ncrcat`
  take many inputs directly, so this would also produce annual means and
  maxima. A wider region adds less time than it might seem, because the input
  is decompressed in full whatever the region.

The measurements behind this, and the optional monitoring used to get them,
are in [DETAILS.md](DETAILS.md).
