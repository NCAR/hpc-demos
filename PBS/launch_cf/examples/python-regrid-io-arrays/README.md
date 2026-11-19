# Wide or Narrow? Job Array Shape and the Queue

`launch_cf` can run the same steps on many nodes for a short time, or on few
nodes for longer, in waves. This example asks how that choice plays with the
PBS queue on Derecho:

- Does a wide job array (many nodes) get a lower priority, or wait longer,
  than a narrow one?
- Which shape finishes sooner, and which costs less?

It submits one **set**: the same work, 1024 ERA5 files, as seven `launch_cf`
jobs of different shapes, all at the same moment, in `main`:

| nodes | 64 | 32 | 16 | 8 | 4 | 2 | 1 |
| ----- | -: | -: | -: | -: | -: | -: | -: |
| waves per node | 1 | 2 | 4 | 8 | 16 | 32 | 64 |

While they wait and run, a sampler records each job's priority and place in
line every minute.

In short: **the shape doesn't change a job's priority**, and the narrow
1-node job was the cheapest, though it finished last. See
[What we found](#what-we-found), and [DETAILS.md](DETAILS.md) for the
measurements.

Read [`../python-regrid-climo`](../python-regrid-climo) first: the steps
here are its two-pass `pario` steps.

## The steps

Each step is one ERA5 day through `calc_anomaly_numba_pario.py` (parallel
decompression, two passes; see
[`../python-regrid-climo`](../python-regrid-climo/DETAILS.md#the-two-pass-versions)),
8 threads, bound to a NUMA domain with `numactl`, 16 at once per node, in
synchronized waves. A wave takes about 11 seconds, so each job asks for
5 minutes plus 20 seconds per wave, rounded up to 5 minutes: 10 minutes for
the widest, 30 for the 1-node job.

## Before you start

- Set `$PBS_ACCOUNT` to your project code.
- The scripts use `launch_cf --sync-waves`. They put a development copy of
  `launch_cf` first in `PATH` until that option is in the installed one.
- `sample_prio.sh` uses `pbs-prio`, from CISL's hpc-scheduling-tools, at the
  path set at the top of the script.
- **One set costs about 330 core-hours**, most of it in the wide jobs, and
  reads 7 × 1024 = 7,168 files.

## Running it

From this directory on a Derecho login node:

```
FIRST=197001 LAST=201912 ./make_filelist.sh   # the ERA5 files, one per day -> era5_t_files.txt
./submit_set.sh s1 0                          # set "s1", from line 0 of the list
./sample_prio.sh s1 &                         # sample the queue until the set has finished
./summarize.py s1                             # once it has
```

`submit_set.sh <set> <first file> [nodes ...]` gives each run its own 1024
consecutive files, from `<first file>` on, and submits the seven runs in a
random order. It records every run in `runs.csv`. Give the next set a
`<first file>` past the last one used, so that no set reads files another has
just read. `DRYRUN=1` writes everything without submitting.

`sample_prio.sh` keeps running until every job of the set has finished, so
start it in the background or in a second terminal. It writes
`samples/<set>/`: the queue order and every subjob's state, once a minute,
and each job's final record from `qstat -x`.

## What to expect

`summarize.py s1` prints one line per run:

```
nodes waves    wall | prio: first max   age s | place: 1st best | wait s: first med last done s |  node-s   nodes   run s  steps ok
   64     1 0:10:00 |  130.14  132.24     657 |   221   184 |    659    798    994   1015 |    1366   64/64     356  1024/1024
    ...
    1    64 0:30:00 |  130.14  133.37     981 |   222   176 |   1011   1011   1011   1900 |     881     1/1     889  1024/1024
```

- `prio` is the job's priority, when first seen and at its highest. Expect
  every run of a set to start at the same priority, whatever its shape.
- `wait s` is the time from submission to the start of the first, median and
  last node; `done s` to the end of the last node.
- `node-s` is the node time used, which is what is charged.

## What we found

Two sets, on 16 November 2026 (in the first, every step failed at once on a
missing import, which was then fixed; its queue data is still valid):

- **Shape doesn't change priority.** Every run of a set had the same
  priority when submitted, and it rose only with time spent waiting.
  Derecho's priority formula has no term for job size, and a queued array is
  one entry in line, however many nodes it asks for.
- **The wide array finished first, the narrow job last.** In the second set,
  64 nodes × 1 wave was done 17 minutes after submission, 1 node × 64 waves
  after 32.
- **The narrow job was the cheapest:** 881 node-seconds, against 1,000 to
  2,100 for the wider shapes, probably because fewer Python processes start
  at once, and fewer nodes read GLADE at once.

So if you can wait, fewer nodes cost less. With two sets, which shape
*starts* first is not settled; [DETAILS.md](DETAILS.md) has both.

## Files

| file | role |
| ---- | ---- |
| `make_filelist.sh` | lists ERA5 temperature files, one per day, in date order |
| `submit_set.sh` | writes the seven command files and submits them at once |
| `sample_prio.sh` | records the queue every minute until the set has finished |
| `summarize.py` | one line per run of a set; `--series` for every sample |
| `run_io_step.sh` | one step, timed |
| `calc_anomaly_numba_pario.py`, `calc_anomaly_numba_io.py` | the two-pass scripts, as in `../python-regrid-climo` |
| `config_env.sh` | sourced by `launch_cf` on each node: `npl-2026a`, `NUMBA_THREADING_LAYER=omp` |
