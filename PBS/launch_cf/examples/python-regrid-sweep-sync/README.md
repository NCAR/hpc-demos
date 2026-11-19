# Threads, Job Arrays and Waves: a Sweep

This example builds on [`../python-regrid`](../python-regrid). It runs the
same Numba calculation as many `launch_cf` steps, one ensemble member per
step, and varies two things:

- **threads per step:** 1, 2, 4 or 8. Every node is packed with 128 threads,
  so it runs 128, 64, 32 or 16 steps at once.
- **waves per node:** how many times over each node's places are filled: 1,
  2, 4 or 8. For the same steps, more waves per node means fewer nodes in
  `launch_cf`'s job array.

Each combination runs twice, **unbound** (Linux places each step's threads
and memory) and **bound** (each step kept in one NUMA domain with `numactl`).

The question it answers: given many steps, how should you lay them out on
nodes so that they cost the least? In short, **bind, and then threads and
waves hardly matter.** See [What we found](#what-we-found), and
[DETAILS.md](DETAILS.md) for every measurement.

## Waves, and why bound runs synchronize them

Give `launch_cf` more steps per node than fit at once, and it runs them in
waves. By default it starts a new step as soon as **any** running step
finishes. That keeps the node busy when step times vary.

A bound step's line names its NUMA domain. The lines count the domains
0, 1, ... 7, 0, 1, ... down the file, so the steps of one wave always fill
the domains evenly. But if the next wave's steps start as soon as any step
finishes, line 17 (domain 0) may start while domain 0's steps are still
running and another domain sits idle.

`launch_cf --sync-waves` prevents this: each wave starts only once every
step of the wave before it has finished. Then the steps running together are
always one wave's lines, two per domain for 8-thread steps. The cost is that
each wave lasts as long as its slowest step. Bound steps of this calculation
take nearly the same time, so that cost is 1 to 3% of node time.

So the bound runs use `--sync-waves`, and the unbound runs don't.

This needs a `launch_cf` with `--sync-waves`; `submit_runs.sh` puts a
development copy first in `PATH` until that option is in the installed one.

## The command files

For `./submit_runs.sh 8 32 2` the unbound command file has 32 lines like

```
OMP_NUM_THREADS=8 ./run_step.sh 1
OMP_NUM_THREADS=8 ./run_step.sh 2
...
```

and the bound one 32 lines like

```
OMP_NUM_THREADS=8 numactl --cpunodebind=0 --membind=0 ./run_step.sh 1
OMP_NUM_THREADS=8 numactl --cpunodebind=1 --membind=1 ./run_step.sh 2
...
OMP_NUM_THREADS=8 numactl --cpunodebind=7 --membind=7 ./run_step.sh 8
OMP_NUM_THREADS=8 numactl --cpunodebind=0 --membind=0 ./run_step.sh 9
...
```

`submit_runs.sh` then runs, for each,

```
launch_cf -q develop -l walltime=0:10:00 -A $PBS_ACCOUNT -N rs-b-t08-n032-w2 \
    --steps-per-node 32 --nthreads 8 --sync-waves cmdfiles/cmdfile.bound.t08.n032.w2
```

(no `--sync-waves` for unbound). It works out the job from its arguments:

```
steps at once  = 128 / threads
steps per node = waves per node * steps at once      (launch_cf --steps-per-node)
nodes          = total steps / steps per node         (the job array)
```

For example `./submit_runs.sh 8 128 2` runs 16 steps at once, 32 per node in
2 waves, as a job array of 4 nodes.

## Running it

From this directory on a Derecho login node, with `$PBS_ACCOUNT` set:

```
./submit_runs.sh 8 32 2                     # one pair: 1 node of 2 waves, under a minute
ITERS=400 WALLTIME=0:30:00 ./sweep.sh       # the whole sweep: 24 jobs
./summarize.py                              # as they finish; --nodes for each node
```

Start with the single pair. It runs in the `develop` queue and costs about
one core-hour. The whole sweep is much bigger: about **430 core-hours**, and
`THREADS="1 2 4 8"`, to include 1-thread steps, adds about 470 more.
`PLACEMENTS=bound` halves either.

`sweep.sh` gives each thread count 8 nodes' worth of one wave, and spreads it
four ways:

| threads | at once | steps | 1 wave  | 2 waves | 4 waves | 8 waves |
| ------- | ------- | ----- | ------- | ------- | ------- | ------- |
| 1       | 128     | 1024  | 8 nodes | 4 nodes | 2 nodes | 1 node  |
| 2       | 64      | 512   | 8 nodes | 4 nodes | 2 nodes | 1 node  |
| 4       | 32      | 256   | 8 nodes | 4 nodes | 2 nodes | 1 node  |
| 8       | 16      | 128   | 8 nodes | 4 nodes | 2 nodes | 1 node  |

Every step does the same work whatever its thread count, so compare runs by
cost per step, not by run time. `ITERS=400` makes each bound step compute for
20 to 170 seconds, so that starting Python (a few seconds) doesn't decide the
comparison. Runs of 1 or 2 nodes go to the `develop` queue and larger ones
to `main`. `QUEUE` overrides this, `DRYRUN=1` writes everything without
submitting, and `THREADS`, `WAVES`, `MAX_NODES` and `PLACEMENTS` narrow the
sweep, e.g. `THREADS=4 PLACEMENTS=bound ./sweep.sh`.

Each run's files are named for its placement, threads, total steps and waves
per node:

```
cmdfiles/cmdfile.bound.t08.n128.w2     the command file
pbs/launch_cf.bound.t08.n128.w2.pbs    the job script launch_cf wrote
logs/launch_cf.bound.t08.n128.w2.log   launch_cf's output, with the job id
rs-b-t08-n128-w2.o<job id>.<index>     PBS output, one per node
stdout-<job id>/                       the steps' output
```

## What to expect

`summarize.py` prints one line per run. The column to compare is
`node-s/step`: each node's time from its first step's start to its last
step's end, summed over the nodes, per step. Expect:

- **bound runs** at about **1.4 node-seconds per step**, with `fill` (the
  share of cores busy with a step) of 97 to 99%;
- **unbound runs** at **1.5 to 2.4**, with step times that vary several-fold.

The other columns are explained at the top of [`summarize.py`](summarize.py)
and in [DETAILS.md](DETAILS.md#what-summarizepy-reports).

## What we found

- **Binding is the big win.** Bound runs cost 1.36 to 1.52 node-seconds per
  step (one run 1.73, slowed by start-up); unbound 1.54 to 2.39.
- **With binding, threads per step hardly matter.** The node moves about
  320 GB/s of memory whether it runs 128 one-thread steps or 16 eight-thread
  ones: its memory, not its cores, is the limit. Choose threads per step for
  other reasons, such as memory per step or how many steps you have.
- **With binding, waves cost nothing.** One node in 8 waves cost the same or
  less than 8 nodes in 1, because fewer Python processes start at once. It
  takes longer to finish, but uses the same node time.
- **Unbound, more waves help only small steps.** At 1 and 2 threads, 8 waves
  cut the cost from 2.39 and 2.05 to 1.60 and 1.54, as short steps filled in
  behind slow ones. At 4 and 8 threads the cost rose, from 1.94 to 2.10 and
  2.20: steps compute more slowly when they start on a busy node. Even at its
  best, unbound cost 13 to 18% more than bound.

An earlier version bound each step to a free domain with lock files instead
of synchronizing waves, and cost the same. It is described in
[DETAILS.md](DETAILS.md#without-synchronized-waves-slots), and proposed for
`launch_cf` in [NCAR/pbstools#17](https://github.com/NCAR/pbstools/issues/17).

## Files

| file                    | role |
| ----------------------- | ---- |
| `submit_runs.sh`        | `./submit_runs.sh <threads> <steps> [waves per node]`: writes an unbound and a bound command file and submits each with `launch_cf` |
| `sweep.sh`              | runs `submit_runs.sh` for each thread count and 1, 2, 4, 8 waves per node |
| `summarize.py`          | one line per finished run; `--nodes` adds a line per node |
| `run_step.sh`           | one step: one member of `calc_anomaly_numba.py`, timed |
| `calc_anomaly_numba.py` | the calculation, the same as in `../python-regrid` |
| `config_env.sh`         | sourced by `launch_cf` on each node before the steps: activates `npl-2026a` |
