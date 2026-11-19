# NUMA Placement for Threaded Python: Advanced

This is the full version of [`../numa-python`](../numa-python). That
example compares only no placement with `numactl` binding; this one also
tries first touch, interleaved memory and per-thread pinning, and looks at
why they help less. Start with `../numa-python` if you only want the
pattern to use.

[`../netcdf-postproc`](../netcdf-postproc) found that pinning made no
difference to independent, single-threaded steps. This example tests the case
that README pointed to instead: **one process whose threads share memory**,
doing work fast enough that memory bandwidth limits its speed.

It has two parts:

- **A single-node trial.** `numa_test.sh` measures whether placement changes
  the speed of this kind of work on a Derecho node. It does: binding each
  process to a NUMA domain gives a full node 1.6 times the throughput (see
  [DETAILS.md](DETAILS.md#results)).
- **A `launch_cf` version.** Real steps, one month of ERA5 each, eight to a
  node, with an unpinned and a pinned command file to compare, as in
  [`../thread-placement`](../thread-placement). Pinned, each node's
  computing finished 2.2 times sooner (see [DETAILS.md](DETAILS.md#launch_cf-results)).

## The computation in brief

[`climatology.py`](climatology.py) computes the time mean and standard
deviation, at every grid point, of one month of hourly ERA5 2 m temperature
(3.1 GB in memory) with 16 threads, each working on its own band of
latitudes. It repeats this many times, so that the computing is long enough
to time next to the 22 s it takes to read the file. The work is limited by
memory bandwidth, so where the memory sits matters. [DETAILS.md](DETAILS.md)
explains the computation and how each run reports where its threads and
memory were.

## The trial

A Derecho node has 8 NUMA domains of 16 cores (see
[`../thread-placement/lscpu.txt`](../thread-placement/lscpu.txt)), so
[`numa_test.sh`](numa_test.sh) runs 8 processes of 16 threads, one per domain,
as `launch_cf` would run 8 steps per node. They load first, then compute
together for 20 seconds, so they compete for memory bandwidth throughout.

| case           | placement                                                      |
| -------------- | -------------------------------------------------------------- |
| `8 free`       | none. The main thread reads the array, so all of it lands in one domain |
| `8 touch`      | none, but each thread copies its own band, so its pages start where it is |
| `8 bind`       | `numactl --cpunodebind=d --membind=d`: threads and memory in domain *d* |
| `8 bind+pin`   | as `bind`, plus `--pin-threads`: each thread calls `os.sched_setaffinity` to fix itself to one core of domain *d* |
| `8 interleave` | `numactl --cpunodebind=d --interleave=all`: memory spread over all 8 domains |
| `1 free`       | one process alone on the node, unpinned                        |
| `1 bind`       | one process alone, bound to domain 0                           |

The last two show why the comparison needs a full node: a process alone has
the node's memory system to itself, so its placement hardly matters.

## Running it

On Derecho, from this directory:

```
qsub -I -A $PBS_ACCOUNT -q main -l select=1:ncpus=128 -l walltime=00:30:00
./numa_test.sh               # 3 repeats of 20 s; or ./numa_test.sh <repeats> <seconds>
```

or as a batch job, `qsub -A $PBS_ACCOUNT numa_test.sh`. The script activates
the `npl-2026a` conda environment if NumPy and netCDF4 aren't already
available. It reads `e5.oper.an.sfc.128_167_2t` for January 2020 from GDEX on
GLADE. Set `ERA5_MONTH=YYYYMM` for another month, `ERA5_FILE` for any NetCDF
file with a 3-D field, or `SYNTHETIC=744` for random data of the same shape.

Each run prints a summary line, and every process's own line goes to
`numa_test.<host>.<time>.log`. The header also reports whether the kernel's
automatic NUMA balancing is on; see [DETAILS.md](DETAILS.md#automatic-numa-balancing-was-off).

## The `launch_cf` version

The same computation as real `launch_cf` steps: each step reads one month of
ERA5 2 m temperature and computes its mean and standard deviation with 16
threads. `launch_cf --nthreads 16 --steps-per-node 8` puts eight steps on a
node, one per NUMA domain's worth of cores. Two command files differ only in
placement:

```
./run_step.sh unpinned .../e5.oper.an.sfc.128_167_2t.ll025sc.2019010100_2019013123.nc
numactl --cpunodebind=0 --membind=0 ./run_step.sh pinned .../e5.oper.an.sfc.128_167_2t.ll025sc.2019010100_2019013123.nc
```

Here "pinned" means the trial's `bind`, numactl only: no thread is pinned
to a core of its own.

Two things differ from the trial:

- **A step has a fixed amount of work**, 200 passes per thread, rather than a
  fixed time, so a slow placement shows up as a slow step, and the node is
  busy until its slowest step finishes. A real analysis would make one pass;
  the repeats stand in for heavier work, so that the compute phase (about
  35 s when pinned) is long enough to measure next to loading.
- **Each step reads its file from GLADE itself.** The load is timed and
  reported, but kept out of the throughput. The steps on a node then wait for
  each other in a node-local directory and start computing together, so that
  a step that loads early doesn't finish before a late one starts.

| file                         | role                                                    |
| ---------------------------- | ------------------------------------------------------- |
| `gen_cmdfile_numa.sh`        | write `cmdfile` or, with `pin`, `cmdfile.pinned`        |
| `run_step.sh`                | one step: `climatology.py` on one month                 |
| `config_env.sh`              | sourced on the compute node: activates `npl-2026a`      |
| `submit_launch_cf.sh`        | submit the unpinned run                                 |
| `submit_launch_cf_pinned.sh` | submit the pinned run                                   |
| `compare_runs.sh`            | compare the runs by their steps                         |

From this directory on a Derecho login node, with `$PBS_ACCOUNT` set:

```
./gen_cmdfile_numa.sh            # 24 months from January 2019 -> cmdfile
./gen_cmdfile_numa.sh pin        #                              -> cmdfile.pinned
./submit_launch_cf.sh
./submit_launch_cf_pinned.sh
./compare_runs.sh                # once both have finished
```

`START=YYYYMM` and `NSTEPS` choose other months. `NSTEPS` must be a multiple
of 8, because the steps on a node wait for eight of them. `make numa-advanced-cmdfiles`
in the parent directory writes both command files.

Each step writes one report line; [DETAILS.md](DETAILS.md#reading-a-steps-output) explains its fields.

## What we found

- For threaded, memory-bound work on a full Derecho node, bind each process
  to one NUMA domain, with `numactl --cpunodebind=d --membind=d`. On this
  workload that gave 1.6 times the throughput and made every process run at
  the same speed.
- Binding the CPUs and the memory together is what matters. Pinning
  individual threads on top of it added nothing.
- Measure placement on a full node. A single process on an idle node shows
  no difference.
- In the `launch_cf` version, pinned steps ran twice as fast as unpinned
  ones, and each node finished computing 2.2 times sooner: a step with a
  fixed amount of work is only as fast as its slowest thread.

Every measurement, and why the other placements fall short, is in
[DETAILS.md](DETAILS.md).
