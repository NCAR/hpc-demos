# ERA5 Anomalies: Measurements

This file holds the measurements behind [README.md](README.md). It covers
two versions of the analysis:

- **[The two-pass versions](#the-two-pass-versions)** (13–16 Nov 2026,
  formerly the `python-regrid-io` example): each hour is measured against
  the mean of its own day, so every file is read twice.
- **[The one-pass version](#the-climatology-and-the-first-analysis-runs-16-nov-2026)**
  (16–18 Nov 2026), the one the README runs: each hour is measured against
  a 1991–2020 climatology built once.

All runs used Derecho CPU nodes (2 × AMD EPYC 7763, 128 cores, 8 NUMA
domains of 16 cores), the `npl-2026a` conda environment and
`NUMBA_THREADING_LAYER=omp`. The cost measure throughout is **node-seconds
per file**: for each node, the time from its first step starting to its last
step ending (from `launch_cf`'s log, to the second), summed over nodes and
divided by the files. One run per configuration unless noted; differences
under about 0.05 node-s per file are within run-to-run noise.

## The two-pass versions

A step computes, for each hour, the anomaly from the mean of the file's own
day, plus the vertical difference and 5-point stencil of
[`../python-regrid`](../python-regrid). That needs the daily mean before any
anomaly, so a step makes two passes: pass 1 reads all 24 hours and averages
them, pass 2 reads each hour again and computes. Every hour is read and
decompressed twice.

| script | reader | memory per step |
| ------ | ------ | --------------- |
| `calc_anomaly_numba_io.py` (`io`) | h5py `read_direct`: HDF5 decompresses on one thread, about 12.6 s per pass, whatever the thread count | 1.5 GB |
| `calc_anomaly_numba_pario.py` (`pario`) | h5py only to find each hour's chunk; a pool of threads reads the compressed bytes with `os.pread` and inflates them with `zlib`, several hours at once (both release the GIL); a Numba kernel undoes HDF5's shuffle filter. As many decompression threads as compute threads | 1.5 GB at 1 thread, about 0.15 GB more per thread |
| `calc_anomaly_numba_pario.py --keep` (`keep`) | as `pario`, but keeps the 24 decompressed hours after pass 1, so each hour is decompressed once | 4.8 GB |

The two readers give the same checksum. Each decompressed hour goes into a
float32 staging buffer and is copied into float64 working arrays first
written by the threads that compute on them, so the arrays stay in those
threads' NUMA domain.

The files were ERA5 days from 1971–2023 that no run had read before. Run
them with `submit_study.sh io|pario|keep ...` and summarize with
`summarize_study.py`, as for the one-pass version.

### One step alone

On an otherwise empty node (one-pass scripts of the time, file cached;
job 8177159), h5py spent about 12.6 s inside HDF5 at every thread count.
pario overlapped decompression across threads: at 16 threads it took
1.07 s against h5py's 12.84 s, 12 times faster.

Where a read spends its time, per pass over one file (job 8176864):

| method | seconds |
| ------ | ------: |
| h5py, compressed file | 12.9 |
| pario, 1 thread + 1 I/O thread | 9.4 |
| pario, 8 threads | 1.3 |
| uncompressed copy on Lustre, h5py, first read | 7.7 |
| uncompressed copy, `pread` with 8 threads, first read | 3.3 |
| uncompressed copy, h5py, cached | 0.7 |

So decompression, not reading from disk, limits a compressed read: reading
the 1.3 GB file took 0.5 to 4 s, against about 11 s to inflate it on one
thread.

**Uncached against cached** (`io_cold.pbs`, job 8205580): reading a file no
one had read recently added at most 0.15 s per step up to 4 threads, and 0.2
to 0.4 s for pario at 8 and 16 threads. Campaign Storage is GPFS, which
caches in its own client pool, not in Linux's page cache, so a "cached"
re-read may not come from local memory.

### Packed nodes: bound against unbound, nodes against waves

36 runs (jobs 8178511–8178547), each case three ways: 4 nodes × 1 wave,
2 × 2, 1 × 4, with 4 × 128 / threads files per case. Bound steps ran under
`numactl` with `--sync-waves`. Node-seconds per file:

| case | bound 4 × 1 | 2 × 2 | 1 × 4 | unbound 4 × 1 | 2 × 2 | 1 × 4 |
| ---- | ---: | ---: | ---: | ---: | ---: | ---: |
| pario, 1 thread  | 0.71 | 0.54 | **0.51** | 0.79 | 0.80 | 0.63 |
| pario, 2 threads | 0.64 | 0.56 | **0.55** | 0.89 | 0.73 | 0.66 |
| pario, 4 threads | 0.95 | 0.70 | **0.57** | 1.24 | 0.80 | 0.72 |
| pario, 8 threads | 1.17 | 0.72 | **0.66** | 0.95 | 0.83 | 0.80 |
| h5py, 1 thread   | 0.86 | 0.80 | **0.76** | 0.86 | 0.85 | 0.82 |
| h5py, 2 threads  | 0.94 | 0.80 | **0.73** | 1.01 | 0.82 | 0.89 |

- **1 node × 4 waves was the cheapest layout in 11 of the 12 series.** In
  the first wave of a large single-wave run, starting Python, h5py and Numba
  took 8–26 s per step; in later waves and 1-node runs, 1–3 s.
- **Bound beat unbound in 16 of 18 comparisons**, mostly in time spent
  waiting for data.
- **Packed, a file costs 2.3 to 3.2 times what it would if every step ran as
  fast as alone** (pario). At 1 thread a step took 23 s alone and 61 s on a
  full node. The node's memory bandwidth is shared: about 350 GB/s by the
  script's own estimate, near the limit found in
  [`../python-regrid-sweep-sync`](../python-regrid-sweep-sync).
- A bound 8-thread pario step took about 10 s, which is what
  [`../python-regrid-io-arrays`](../python-regrid-io-arrays) uses to size its
  wall-time requests.

**Equal files at every thread count** (jobs 8180500–8180503): 512 files on one
node at 2 and 4 threads cost 0.54 and 0.58 bound, against 0.51 at 1 thread.
The order held, so 1 thread is not cheapest only because its run had more
files. Idle cores were 5–6% of node time in every bound run; the extra cost of
more threads is inside the step (61 to 69 core-seconds per file from 1 to 4
threads).

### Decompress once: `--keep`

512 files on one node (jobs 8205423–8205426):

| case | pario | `--keep` |
| ---- | ----: | -------: |
| bound, 4 threads   | 0.58 | **0.45** |
| bound, 8 threads   | 0.67 | 0.53 |
| unbound, 4 threads | 0.73 | 0.53 |

Keeping the day in memory halved the time spent waiting for data (bound,
4 threads: 22.9 to 11.7 core-seconds per file), and made `--keep` at 4
threads the cheapest two-pass layout, 12% below plain pario at 1 thread. At
4.8 GB per step it fits only at 4 or 8 threads per step.

This led to the one-pass version: with a climatology computed once, a step
needs only pass 2, and no extra memory.

## The climatology and the first analysis runs (16 Nov 2026)

**Building the climatology** (job 8207608): 366 steps, all succeeded; 4
nodes, 3 synchronized waves, 12.5 minutes, **107 core-hours**. Each step read
its 30 files in about 4 minutes and wrote its 154 MB file in 0.3 s; 53 GB in
all.

**Analysis**, 512 files on one node, bound (jobs 8207720–8207722), compared
with the best two-pass layouts ([above](#the-two-pass-versions)):

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
  | pario, 17 Nov    | **0.33** | 0.35 | 0.36 | 0.51 | 0.62 |
  | h5py, 17 Nov     | 0.48 | 0.47 | 0.62 | 1.06 | – |

  Packed, the readers are much closer than alone: one step per core already
  decompresses 128 files in parallel. Steps slow down 2–4× against running
  alone; the memory-bound compute slows most (about 10× at 1 thread).
* **Nodes against waves, 512 files per case** (4 × t, 2 × 2t, 1 × 4t waves at
  t threads), bound and unbound: one node is the cheapest layout in 11 of 12
  series (12 of 12 in the repeat); bound beats unbound most at 1 thread (0.36
  against 0.46, repeat 0.33 against 0.43). 4-node jobs in `main` waited up to 23
  minutes for their last node, while 1- and 2-node `develop` jobs started
  within seconds.

### Repeat (17 Nov 2026)

`./run_study.sh 19984` ran the whole chain again (jobs 8218722–8218766, about
430 core-hours), plus the three earlier pario runs and two more `solo.pbs`
runs. Lines 20451 onward of `era5_t_files.txt` are the 19,700 files whose
access time showed no read for at least 24 hours; the list as of 16 Nov is
`era5_t_files.20261116.txt`.

* Node-seconds per file changed by a median of 7% across the 39 runs: 5% on 1
  or 2 nodes (largest 18%), 11% on 4 nodes (largest 25%).
* Unshuffle and compute hardly change between runs. Start-up changes most: a
  packed first wave's steps took 2–27 s to start. Waiting for data comes next.
* Every ranking held: pario against h5py packed, one node against more,
  bound against unbound for pario at 1–4 threads. Two claims did not: h5py at
  2 threads against 1 (0.47 against 0.48 in the repeat), and 4 nodes × 1 wave
  costing the same bound or unbound (0.43 against 0.57).
* One step alone repeats within 0.7 s at every thread count (four runs).

### Nodes against waves a third time (18 Nov 2026)

All 36 nodes-against-waves runs of `run_study.sh` again (jobs 8226947–8226983, about 380 core-hours,
`logs/run_studyC.20261118.log`), from lines 40000–58431 of
`era5_t_files.txt`. The appended files are the least recently read, each
last read at least 16 hours earlier. These runs were submitted at once, not
chained. The 12 four-node `main` jobs started together, alongside the
`develop` jobs, and for 12 minutes up to 20 nodes read at once. The 17 runs in
that window cost 17% more than the mean of 16 and 17 Nov: pario 28% more,
almost all of it waiting for data, and h5py 2% more. The 19 later runs, two or
three nodes at a time, cost 2% less. Averaged over the three runs, one node
is the cheapest layout in 11 of 12 series. The exception is pario bound at 8
threads, whose 18 Nov 1-node run shared the file system. Four nodes is the
most expensive layout in all 12 series.

Two bumps in the three-run means for pario bound at 2 threads come from
single 18 Nov runs, not from the layout:

* **Start-up, 1 node × 8 waves**, does not keep falling with fewer nodes.
  The 18 Nov run's first wave took 22.6 s to start, against 8.6 and 9.5 s in
  the other two runs (later waves 1.4–1.9 s). Without it, the 1-node layout is
  about 0.04 node-s per file, against 0.065 for 2 nodes × 4 waves.
* **Waiting for data** rises from 2 × 4 (0.095 node-s per file) to 1 × 8
  (0.103). The 18 Nov 1-node run (job 8226958) waited 10–13 s per step for
  its first six waves, then 3–6 s, against 2–5 s in the 17 Nov run. It ran
  outside the window when 20 nodes read at once, so campaign storage was
  probably busy with other users' reads. The 17 Nov runs follow the trend
  (0.061 against 0.089); the 16 Nov ones are within noise (0.093 against
  0.082).

A 1-node run reads during one stretch of time, so one slow patch of storage
moves its whole result. The mean of three runs still moves by 0.02–0.05
node-s per file.
