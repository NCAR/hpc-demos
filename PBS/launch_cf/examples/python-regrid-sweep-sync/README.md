# Threads, Job Arrays and Waves with `launch_cf --sync-waves`

This directory builds on [`../python-regrid`](../python-regrid). It runs the
same Numba calculation as many `launch_cf` steps, one ensemble member per
step, and varies two things:

- **threads per step:** 2, 4 or 8. Every node is packed with 128 threads, so
  it runs 64, 32 or 16 steps at once.
- **waves per node:** how many times over each node's places are filled: 1,
  2, 4 or 8. For the same steps, more waves per node means fewer nodes in
  `launch_cf`'s job array.

Each combination runs twice, **unbound** (Linux places each step's threads
and memory) and **bound** (each step kept in one NUMA domain with `numactl`).

Everything about running the steps is `launch_cf`'s: how many run at once,
which node runs which, and when the next starts. `run_step.sh` runs one
member, and the command file says how.

This needs the `launch_cf` from the `launch_cf-multiple-waves` branch of
[NCAR/pbstools](https://github.com/NCAR/pbstools); `submit_runs.sh` puts a
development copy first in `PATH`.

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
each wave lasts as long as its slowest step. For bound steps that is small:
they take nearly the same time (see
[`../python-regrid-sweep-slotctl`](../python-regrid-sweep-slotctl), where
bound steps of a run varied by 1 to 5%).

So the bound runs use `--sync-waves`, and the unbound runs don't.

## Files

| file                    | role |
| ----------------------- | ---- |
| `submit_runs.sh`        | `./submit_runs.sh <threads> <steps> [waves per node]`: writes an unbound and a bound command file and submits each with `launch_cf` |
| `sweep.sh`              | runs `submit_runs.sh` for threads 2, 4, 8 and 1, 2, 4, 8 waves per node: 24 jobs |
| `summarize.py`          | one line per finished run; `--nodes` adds a line per node |
| `run_step.sh`           | one step: one member of `calc_anomaly_numba.py`, timed |
| `calc_anomaly_numba.py` | the calculation, the same as in `../python-regrid` |
| `config_env.sh`         | sourced by `launch_cf` on each node before the steps: activates `npl-2026a` |

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
2 waves, as a job array of 4 nodes. Each run's files are named for its
placement, threads, total steps and waves per node:

```
cmdfiles/cmdfile.bound.t08.n128.w2     the command file
pbs/launch_cf.bound.t08.n128.w2.pbs    the job script launch_cf wrote
logs/launch_cf.bound.t08.n128.w2.log   launch_cf's output, with the job id
rs-b-t08-n128-w2.o<job id>.<index>     PBS output, one per node
stdout-<job id>/                       the steps' output
```

## Running it

From this directory on a Derecho login node, with `$PBS_ACCOUNT` set:

```
./submit_runs.sh 8 32 2                     # one pair: 1 node of 2 waves
ITERS=400 WALLTIME=0:30:00 ./sweep.sh       # all 24 jobs
./summarize.py                              # as they finish; --nodes for each node
```

`sweep.sh` gives each thread count 8 nodes' worth of one wave, and spreads it
four ways:

| threads | at once | steps | 1 wave  | 2 waves | 4 waves | 8 waves |
| ------- | ------- | ----- | ------- | ------- | ------- | ------- |
| 2       | 64      | 512   | 8 nodes | 4 nodes | 2 nodes | 1 node  |
| 4       | 32      | 256   | 8 nodes | 4 nodes | 2 nodes | 1 node  |
| 8       | 16      | 128   | 8 nodes | 4 nodes | 2 nodes | 1 node  |

Every step does the same work whatever its thread count, so compare runs by
`node-s/step`, not by run time.

`ITERS=400` makes each step compute for 20 to 110 seconds, so that starting
Python (a few seconds) doesn't decide the comparison. Runs of 1 or 2 nodes
go to the `develop` queue and larger ones to `main`. `QUEUE` overrides this,
`WALLTIME` sets the limit per node, `DRYRUN=1` writes everything without
submitting, and `THREADS`, `WAVES`, `MAX_NODES` and `PLACEMENTS` narrow the
sweep, e.g. `THREADS=4 PLACEMENTS=bound ./sweep.sh`.

## What summarize.py reports

It takes when each step started and finished from `launch_cf`'s own PBS
output ("launching step", "finished step"), and what each step computed from
its output in `stdout-<job id>/`.

| column    | meaning |
| --------- | ------- |
| `nodes`, `waves` | nodes in the job array, and waves per node; `sync` when synchronized |
| `ok`      | steps that finished cleanly with a result, of all steps |
| `comp s`  | the steps' compute phase: mean (slowest) |
| `GB/s`    | each step's estimated memory bandwidth: mean (min – max) |
| `start s` | the rest of a step, mostly starting Python and loading Numba: mean |
| `node-s`  | each node's first step start to last step end, summed over nodes |
| `PBS`     | node time as `launch_cf` reports it, summed: also counts the job's own start |
| `node-s/step` | node-s / steps: the cost per step to compare across runs |
| `fill`    | share of the nodes' cores busy with a step during node-s |
| `imbal`   | per node, its time / (its total step time / steps at once): 1.00 when its steps pack perfectly; mean and worst node |
| `wall s`  | first start to last end over all nodes; depends also on when PBS started each array index |

With synchronized waves, the time a node spends waiting for each wave's
slowest step shows up as lower `fill` and higher `imbal`. `launch_cf`
reports times to the second, so these columns need steps much longer than a
second to mean much: use `ITERS=400`.

## Results

`./submit_runs.sh 8 32 2` (jobs 8169093, 8169094, the default 40 iterations)
checks that it works: all 32 steps of each ran, and the bound run's PBS
output shows `launch_cf` starting wave 2 only after wave 1 had finished.

The full sweep has not been run yet. For comparison, the same sweep in
[`../python-regrid-sweep-slotctl`](../python-regrid-sweep-slotctl), where
bound steps found their domain without synchronizing waves, cost per step
(node-seconds):

| threads | unbound | bound  |
| ------- | ------- | ------ |
| 2       | 1.56 – 2.49 | 1.37 – 1.40 |
| 4       | 2.02 – 2.14 | 1.37 – 1.51 |
| 8       | 2.10 – 2.24 | 1.40 – 1.49 |
