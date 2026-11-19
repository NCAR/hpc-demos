# NUMA Placement for a Numba Stencil Calculation

This example runs 32 copies of a threaded Python calculation, written with
[Numba](https://numba.pydata.org/), as `launch_cf` steps on Derecho. It
compares two ways of running them:

- **unbound:** the steps run as they are, and Linux decides where their
  threads run and where their memory goes.
- **bound:** each step is kept inside one NUMA domain with `numactl`.

It runs each of these in two layouts. One uses 2 nodes with 16 steps per
node, and the other uses 1 node that runs 16 steps at a time.

In short, binding made the calculation **about 1.25 times faster on average,
and the slowest step 1.45 times faster**, and every bound step ran at the same
speed. But each step is short, and on a fresh node starting Python takes
longer than calculating, so the jobs as a whole show the difference only
roughly. See [What we found](#what-we-found), and [DETAILS.md](DETAILS.md)
for the measurements.

The pattern to copy is one prefix on each line of the command file:

```
numactl --cpunodebind=<d> --membind=<d> <your step>
```

with *d* from 0 to 7. [`../numa-python`](../numa-python) explains why this
helps, and [`../thread-placement`](../thread-placement) shows where threads
land with and without it.

## Background in brief

A Derecho CPU node has 128 cores in **8 NUMA domains** of 16 cores. Each domain
has its own memory, about 30 GB, and a core reads its own domain's memory
fastest. Without `numactl`, Linux may run a program's threads in several
domains, far from its memory, and move them around while they run.

- `--cpunodebind=d` keeps the program and all its threads on domain *d*'s
  cores.
- `--membind=d` takes all its memory from domain *d*.

This matters most for work that reads a lot of memory and does little
arithmetic on it, like the calculation here.

## The calculation

[`calc_anomaly_numba.py`](calc_anomaly_numba.py) stands in for typical
post-processing of model output. It makes up its own data, so it reads no
files:

1. It creates three 3-D arrays of 32 levels × 720 latitudes × 1440 longitudes,
   in double precision: a temperature field, a climatology, and an output
   array. Each is 265 MB, so a step uses about 0.9 GB of memory.
2. It runs this 40 times (`--iters`) over every grid point:
   - the anomaly from the climatology, weighted by level;
   - a centred difference between the levels above and below;
   - a 5-point horizontal stencil, the point and its four neighbours, like the
     ones used in smoothing and regridding.

The loops are compiled by Numba with `@njit(parallel=True)`, and the
latitudes are shared among the threads. Each step uses 8 threads, set by
`OMP_NUM_THREADS=8` in the command file; the script passes it on to Numba as
`NUMBA_NUM_THREADS`.

Two details help it run well:

- **Each thread fills in the latitudes it will later compute on.** Linux puts
  memory in the domain of the thread that first writes it, so each thread's
  part of the arrays starts out in its own domain. That only stays true if the
  thread stays in that domain, which `numactl` guarantees and an unbound run
  doesn't.
- **The compiled code is cached** (`cache=True`) in `__pycache__` next to the
  script, so only the first run after a change pays for compiling it.

The `--member` number only shifts the values a little, as if each step were
a different ensemble member, so all steps do the same amount of work.

## The runs

| script                    | command file      | nodes | steps per node | at once per node |
| ------------------------- | ----------------- | ----- | -------------- | ---------------- |
| `submit_unbound.sh`       | `cmdfile.unbound` | 2     | 16             | 16               |
| `submit_bound.sh`         | `cmdfile.bound`   | 2     | 16             | 16               |
| `submit_unbound_waves.sh` | `cmdfile.unbound` | 1     | 32             | 16               |
| `submit_bound_waves.sh`   | `cmdfile.bound`   | 1     | 32             | 16               |

Each node runs 16 steps of 8 threads at once, which fills its 128 cores. In
the bound command file the domain number counts 0 to 7 down the file and
starts over, so each domain holds 2 steps at a time, 16 threads on its 16
cores:

```
OMP_NUM_THREADS=8 OPENBLAS_NUM_THREADS=8 MKL_NUM_THREADS=8 ./run_step.sh 1
OMP_NUM_THREADS=8 OPENBLAS_NUM_THREADS=8 MKL_NUM_THREADS=8 numactl --cpunodebind=0 --membind=0 ./run_step.sh 1
```

(the first line is from `cmdfile.unbound`, the second from `cmdfile.bound`).

The 2-node runs are a PBS job array of 2, one node for each 16 steps. PBS may
give both to the same node, one after the other.

The `_waves` scripts ask for all 32 steps on one node with
`--steps-per-node 32 --nthreads 8`. Only 16 fit at once, so `launch_cf` starts
16, and **starts the next one as soon as any step finishes**. It does not wait
for all 16 to finish. This needs a newer `launch_cf` than the one installed on
Derecho, which rejects that request because 32 × 8 is more than 128 cores. The
submit scripts put a development copy of
[NCAR/pbstools](https://github.com/NCAR/pbstools) first in `PATH`.

| file                   | role |
| ---------------------- | ---- |
| `generate_runs.sh`     | writes both command files and all four submit scripts |
| `run_step.sh`          | one step: runs `calc_anomaly_numba.py` under `/usr/bin/time` |
| `config_env.sh`        | sourced on the compute node: activates the `npl-2026a` conda environment |
| `calc_anomaly_numba.py`| the calculation |

## Running it

From this directory on a Derecho login node, with `$PBS_ACCOUNT` set to your
project code:

```
./generate_runs.sh
./submit_unbound.sh
./submit_bound.sh
./submit_unbound_waves.sh
./submit_bound_waves.sh
```

They use the `develop` queue with a 5-minute limit, and each finishes in
under 20 seconds once it starts. Every step writes to
`stdout-<job id>/step-NNNNN.out`, and `launch_cf.o<job id>` records when each
step started and finished.

### Reading a step's output

```
[Member 001 | Host: dec1931 | Threads:  8] Alloc: 0.21s | Compute: 2.35s | Est. BW:  18.1 GB/s | Checksum: 4.3028
Elapsed time: 0:10.08 | Max RSS: 889544 KB | Major faults: 6 | Swaps: 0 | ...
```

| field          | meaning |
| -------------- | ------- |
| `Threads`      | the threads Numba used |
| `Alloc`        | seconds to fill the three arrays |
| `Compute`      | seconds for the 40 iterations: the part placement affects |
| `Est. BW`      | estimated memory traffic per second during `Compute`: 4 array-sized streams per iteration |
| `Checksum`     | a check value; it depends only on the member, not on placement |
| `Elapsed time` | the whole step, from `/usr/bin/time`, including starting Python and loading Numba |
| `Max RSS`      | the most memory the step used, here about 0.9 GB |

## What we found

- **Binding made the calculation about 1.25 times faster** on average, and
  the slowest step 1.45 times faster. Every bound step ran at nearly the same
  speed; unbound steps varied from 13.6 to 25.3 GB/s.
- **Starting Python is a big part of a short step.** On a fresh node, a step
  took 9 to 11 seconds, mostly before computing; once the node had Python and
  Numba in memory, 3 to 4. Placement can only speed up the computing.
- **Waves used one node instead of two**, and no more node-seconds: 15
  against 15 bound, and 17 against 25 unbound. The second wave's steps
  started on a node that already had Python loaded.

The run-by-run results are in [DETAILS.md](DETAILS.md).

## Using this with your own work

- **Fill each domain exactly.** Here 2 steps of 8 threads share each 16-core
  domain. With 16 threads per step, use 1 step per domain and
  `--steps-per-node 8 --nthreads 16`.
- **Set the thread count in the command file.** `OMP_NUM_THREADS` set on a
  line overrides the one PBS sets from `--nthreads`. Numba uses
  `NUMBA_NUM_THREADS`, which this script copies from `OMP_NUM_THREADS`; in your
  own code set it directly.
- **Cache compiled Numba code** with `@njit(cache=True)`, so that every step
  doesn't compile the same functions again.
- **Stay within a domain's memory.** With `--membind`, all the steps in a
  domain share its roughly 30 GB. Here they use 1.8 GB.
- **Check what the time goes to.** If most of a step is starting up or
  reading files, binding won't change much; see
  [`../numa-python`](../numa-python) for a case where computing dominates and
  binding made steps twice as fast.
