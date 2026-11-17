# One pass per file: ERA5 anomalies against a long-term climatology

This directory builds on [`../python-regrid-io`](../python-regrid-io). There,
each ERA5 day's anomaly is measured against the mean of that same day, so
every file is read and decompressed twice: once for the mean, then again for
the anomaly (or kept whole in memory with `--keep`).

Here the reference is the **1991–2020 climatology** of the calendar day,
computed once. Each file then needs only **one pass**, and the work splits
into two `launch_cf` jobs:

1. **Build the climatology, once.** `make_climo.sh` runs 366 steps, one per
   calendar day. Each step averages that day's 24 hourly fields over the 30
   years (8 leap years for 29 February) and writes one uncompressed field,
   `climo/T_1991-2020_MMDD.h5` (37 × 721 × 1440 float32, 154 MB).
2. **Analyse any number of days, one pass each.**
   `calc_anomaly_numba_climo.py` reads the day's climatology, then reads,
   decompresses and computes each hour once.

This is also how such analyses are usually done in practice: anomalies are
departures from a climate normal, not from the same day's mean.

## Files

| file | role |
| ---- | ---- |
| `make_climo.sh` | submits the climatology build: 366 bound steps, 4 threads each, 4 nodes (`NODES`, `THREADS`, `QUEUE`, `WALLTIME`, `DAYS`, `DRYRUN`). Leaves out days already built, so running it again finishes a partial build |
| `make_climo_day.py` | one calendar day: `./make_climo_day.py 0101 [--first 1991 --last 2020 --out climo]` |
| `run_climo_day.sh` | one build step, timed by `/usr/bin/time` |
| `calc_anomaly_numba_climo.py` | the one-pass analysis of one ERA5 file; `--h5py` reads each hour with h5py (HDF5 decompresses on one thread) instead of the parallel decompression |
| `submit_study.sh` | `./submit_study.sh <climo\|climoh5\|io\|pario\|keep> <bound\|unbound> <threads> <nodes> <waves> <first file>`: packs nodes with analysis steps, one file per step |
| `run_io_step.sh` | one analysis step, timed (`climo`: pario reader, `climoh5`: h5py reader) |
| `solo.pbs` | one step alone on a develop node, both readers, 1–128 threads, uncached then cached |
| `run_study.sh` | the 16 Nov study as one chain of jobs: `solo.pbs`, one packed node, then nodes × waves × placement |
| `summarize_study.py` | one line per finished `submit_study.sh` run |
| `era5_t_files.txt` | the ERA5 files to analyse, none in the climatology years: 4 April 1971 to 1979 (lines 0–3193, as first written), then 1940 to March 1971, 1980–1990 and 2021–2025 |
| `make_filelist.sh` | writes a file list for other months |
| `calc_anomaly_numba_io.py`, `calc_anomaly_numba_pario.py` | the kernels and the parallel decompression, copied unchanged from `../python-regrid-io` |
| `config_env.sh` | sourced by `launch_cf` on each node: `npl-2026a`, `NUMBA_THREADING_LAYER=omp` |

## Running it

```bash
./make_climo.sh                               # once; about 15 minutes on 4 nodes
./submit_study.sh climo bound 1 1 4 0         # 512 files on one develop node
./summarize_study.py
```

## Results (16 Nov 2026)

**Building the climatology** (job 8207608): 366 steps, all succeeded; 4
nodes, 3 synchronized waves, 12.5 minutes, **107 core-hours**. Each step read
its 30 files in about 4 minutes and wrote its 154 MB file in 0.3 s; 53 GB in
all.

**Analysis**, 512 files on one node, bound (jobs 8207720–8207722), compared
with the best layouts of `../python-regrid-io`:

| script | threads per step | node-s per file | peak memory per step |
| ------ | ---------------: | --------------: | -------------------: |
| `climo`, one pass | 1 | **0.36** | 1.5 GB |
| `climo`, one pass | 2 | 0.37 | 1.6 GB |
| `climo`, one pass | 4 | 0.40 | 1.9 GB |
| `pario --keep`, same-day mean | 4 | 0.45 | 4.8 GB |
| `pario`, same-day mean, two passes | 1 | 0.51 | 1.5 GB |

One pass halves the core time spent waiting for data and unshuffling (18
against 36 core-seconds per file at 1 thread) and needs no more memory than
two-pass `pario`, so 1 thread per step, all 128 cores busy, is again the
cheapest layout.

The climatology is a one-time cost: about 3,000 node-seconds, or 3,000 ÷ N
node-seconds per file over N files analysed. Over all ~31,000 ERA5 days since
1940 that adds 0.10 (0.46 in total); over 30 years of days, 0.27 (0.63 in
total, more than two-pass `pario`). It pays off when it is reused, by many
files or many analyses.

The full write-up, with the `python-regrid-io` studies, is the "ERA5 I/O
scaling studies" report (Study 7).

## h5py against pario, one pass (16 Nov 2026)

`./run_study.sh` (jobs 8207950–8207988, about 360 core-hours, every step
succeeded) compares the two readers of `calc_anomaly_numba_climo.py`:

* **One step alone** (`solo.pbs`): h5py takes 13–16 s per file at every
  thread count, because HDF5 decompresses on one thread. pario takes 12.2 s at
  1 thread and 2.3–2.6 s from 16 threads up. Reading uncached adds at most 0.6 s.
* **One packed node, bound, 512 files**, node-seconds per file:

  | threads per step | 1 | 2 | 4 | 8 | 16 |
  | ---------------- | -: | -: | -: | -: | -: |
  | pario (`climo`)  | **0.36** | 0.37 | 0.40 | 0.49 | 0.61 |
  | h5py (`climoh5`) | 0.49 | 0.43 | 0.67 | 1.07 | – |

  Packed, the readers are much closer than alone: one step per core already
  decompresses 128 files in parallel. Steps slow down 2–4× against running
  alone; the memory-bound compute slows most (about 10× at 1 thread).
* **Nodes against waves, 512 files per case** (4 × t, 2 × 2t, 1 × 4t waves at
  t threads), bound and unbound: one node is the cheapest layout in 11 of 12
  series; bound beats unbound most at 1 thread (0.36 against 0.46); 4 nodes ×
  1 wave cost 0.47 for both placements. 4-node jobs in `main` waited up to 23
  minutes for their last node, while 1- and 2-node `develop` jobs started
  within seconds.

The full write-up is the "ERA5 one-pass studies" report.

