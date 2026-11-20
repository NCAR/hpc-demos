# ERA5 Anomalies, One File per Step

This example computes temperature anomalies from ERA5 reanalysis files on
GLADE against a 1991–2020 climatology. Each `launch_cf` step processes one
day's file. The example runs as two `launch_cf` jobs:

1. **Build the climatology, once.** This job runs 366 steps, one per
   calendar day. Each step averages that day's 24 hourly fields over the 30
   years and writes one uncompressed field to `climo/`.
2. **Analyse the files.** This job runs one step per ERA5 day. Each step
   reads its day's climatology, then reads, decompresses and computes on
   each hour of the file once.

The example shows three things:

- **A two-stage workflow.** A one-time job produces output that many later
  steps reuse.
- **Steps that read real, compressed data.** Decompressing the file costs
  more than computing on it, so how a step decompresses matters.
- **How to pack steps onto nodes for the least cost.** For this workload,
  1 thread per step, bound to a NUMA domain, all 128 cores busy, and one
  node running several waves, was the cheapest.

Read [`../python-regrid`](../python-regrid) first. It introduces the
calculation, NUMA binding and waves. The full measurements behind the advice
here, including the two-pass versions this example replaced, are in
[DETAILS.md](DETAILS.md).

## The data and the calculation

Each input file holds one day of ERA5 temperature on pressure levels
(`e5.oper.an.pl.128_130_t`, from GDEX dataset d633000 on GLADE). It has 24
hours × 37 levels × 721 latitudes × 1440 longitudes, which is 3.7 GB of
32-bit values, compressed to about 1.3 GB. Each hour is stored as one compressed chunk, so
a program has to read and decompress a chunk to use an hour.

For each hour, a step uses Numba threads to compute the anomaly from the
climatology of its calendar day. It adds the vertical difference and the
5-point horizontal stencil of `../python-regrid`.

A step can read its file in two ways:

- **`climo`** (the default). A pool of threads reads the compressed bytes
  and decompresses several hours at once.
- **`climoh5`** (`--h5py`). HDF5 reads each hour through h5py, and
  decompresses on one thread whatever the step's thread count.

## Before you start

- Set `$PBS_ACCOUNT` to your project code.
- The scripts use `launch_cf --sync-waves`. They put a development copy of
  `launch_cf` first in `PATH` until that option is in the installed one.
- Building the climatology costs about **107 core-hours**. The analysis run
  below costs about 7.

## Running it

From this directory on a Derecho login node:

```bash
./make_climo.sh                         # once: 366 steps on 4 nodes, about 15 minutes
./submit_study.sh climo bound 1 1 4 0   # 512 files on one develop node
./summarize_study.py                    # once it has finished
```

`make_climo.sh` writes one file per day, `climo/T_1991-2020_MMDD.h5`, of
154 MB. If some days fail, run it again. It submits only the days that are
missing.

`submit_study.sh climo bound 1 1 4 0` uses the `climo` reader, binds the
steps to NUMA domains, and runs 1 thread per step on 1 node in 4 waves,
starting at line 0 of [`era5_t_files.txt`](era5_t_files.txt). A node runs 128 one-thread steps at
once, so 4 waves is 512 files. Each wave starts once the one before it has
finished.

## What to expect

`summarize_study.py` prints one line per run. The column to watch is
`node-s/step`, which is the node time the run used divided by the number of
files. It is the cost per file, and it lets you compare runs of any shape. Expect about **0.33 to 0.36
node-seconds per file**, and every one of the 512 steps `ok`.

A one-thread step takes about 12 seconds alone on a node, but about 40
seconds on a full node, because 128 steps share the node's memory bandwidth
and its link to GLADE. That is expected. The cost per file is what
matters, not the time of one step.

Results vary from run to run by about 7%, and by up to 25% on 4 nodes. Most
of the variation comes from how busy GLADE is while the files are read.

## Trying other layouts

```
./submit_study.sh <climo|climoh5|io|pario|keep> <bound|unbound> <threads> <nodes> <waves> <first file>
```

Give each run its own `<first file>`, so that no run reads files another has
just read. For example, `./submit_study.sh climoh5 bound 1 1 4 512` runs the
h5py reader on the next 512 files.

`io`, `pario` and `keep` are the earlier two-pass scripts. They measure each
hour against the mean of its own day instead of a climatology. See
[DETAILS.md](DETAILS.md#the-two-pass-versions).

## What we found

- **Bind, and use 1 thread per step.** Bound 1-thread steps cost 0.33–0.36
  node-s per file on one node, 8-thread steps about 0.5, and unbound 1-thread
  steps 0.38–0.46.
- **One node in several waves beats several nodes in one.** The same 512
  files cost more spread over 2 or 4 nodes, largely because hundreds of
  Python processes starting at once start slowly. Also, the 1-node jobs in
  `develop` started within seconds, while 4-node jobs in `main` waited up
  to 23 minutes.
- **Parallel decompression helps most when a step runs alone.** One step
  alone is 5 times faster with `climo` than with `climoh5` at 16 threads. On a
  full node, 128 one-thread steps already decompress 128 files at once, and
  `climo` is only about 30% cheaper.
- **The climatology pays off when it is reused.** The 107 core-hours spread
  over all 31,000 ERA5 days since 1940 add 0.10 node-s per file.

## Files

| file | role |
| ---- | ---- |
| `make_climo.sh` | submits the climatology build: 366 bound steps, 4 threads each, 4 nodes (`NODES`, `THREADS`, `QUEUE`, `WALLTIME`, `DAYS`, `DRYRUN`) |
| `make_climo_day.py`, `run_climo_day.sh` | one build step: one calendar day |
| `calc_anomaly_numba_climo.py` | the one-pass analysis of one ERA5 file; `--h5py` for the h5py reader |
| `submit_study.sh` | packs nodes with analysis steps, one file per step |
| `run_io_step.sh` | one analysis step, timed |
| `summarize_study.py` | one line per finished `submit_study.sh` run |
| `era5_t_files.txt` | the ERA5 files to analyse, none from the climatology years |
| `make_filelist.sh` | writes a file list for other months |
| `config_env.sh` | sourced by `launch_cf` on each node: `npl-2026a`, `NUMBA_THREADING_LAYER=omp` |
| `calc_anomaly_numba_io.py`, `calc_anomaly_numba_pario.py` | the two-pass scripts (h5py and parallel decompression) |
| `solo.pbs`, `io_cold.pbs` | one step alone on a node, at 1 to 128 threads, uncached then cached: one-pass and two-pass scripts |
| `run_study.sh` | the 16 Nov study as one chain of jobs; see [DETAILS.md](DETAILS.md) |
