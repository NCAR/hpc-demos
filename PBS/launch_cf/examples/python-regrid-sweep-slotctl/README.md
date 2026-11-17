# Threads, Job Arrays and Waves: a Sweep, with Slots

> **The simpler version is [`../python-regrid-sweep-sync`](../python-regrid-sweep-sync).**
> It puts `numactl` in the command file and lets `launch_cf --sync-waves`
> keep each wave's bound steps together. This directory does it without
> synchronizing waves: each bound step claims a free "slot" on its node
> with a lock file (see below), which takes more machinery in `run_step.sh`.
> It is kept for its results.

This directory builds on [`../python-regrid`](../python-regrid). It runs the
same Numba calculation as many `launch_cf` steps, and varies two things:

- **threads per step:** 2, 4 or 8. Every node is packed with 128 threads, so
  it runs 64, 32 or 16 steps at once.
- **waves per node:** how many times over each node's slots are filled, 1, 2,
  4 or 8. For a given number of steps, more waves per node means fewer nodes
  in `launch_cf`'s job array: 8 nodes of 1 wave, down to 1 node of 8 waves.
  `launch_cf` starts a new step on a node as soon as any of its steps
  finishes, so after the first wave the steps no longer start together.

Each combination runs **unbound** (Linux places threads and memory) and
**bound** (each step kept in one NUMA domain). The questions are how the
thread count changes the cost per step, and how well waves keep the nodes
busy when step times vary, as they do unbound.

This needs the `launch_cf` from the `launch_cf-multiple-waves` branch of
[NCAR/pbstools](https://github.com/NCAR/pbstools); `submit_runs.sh` puts a
development copy first in `PATH`.

## Files

| file                    | role |
| ----------------------- | ---- |
| `submit_runs.sh`        | `./submit_runs.sh <threads> <steps> [waves per node]`: writes an unbound and a bound command file and submits each with `launch_cf` |
| `sweep.sh`              | runs `submit_runs.sh` for threads 2, 4, 8 and 1, 2, 4, 8 waves per node: 24 jobs |
| `summarize.py`          | one line per finished run; `--nodes` adds a line per node, `--csv` writes every step |
| `run_step.sh`           | one step, unbound or bound |
| `calc_anomaly_numba.py` | the calculation, the same as in `../python-regrid` |
| `config_env.sh`         | sourced on the compute node: activates `npl-2026a` |

`submit_runs.sh` works out the job from its arguments:

```
steps at once  = 128 / threads
steps per node = waves per node * steps at once      (launch_cf --steps-per-node)
nodes          = total steps / steps per node         (the job array)
```

For example `./submit_runs.sh 8 128 2` runs 16 steps at once, 32 per node in
2 waves, as a job array of 4 nodes. Each run's files are named for its
placement, threads, total steps and waves per node:

```
cmdfiles/cmdfile.unbound.t08.n128.w2     the command file
pbs/launch_cf.unbound.t08.n128.w2.pbs    the job script launch_cf wrote
logs/launch_cf.unbound.t08.n128.w2.log   launch_cf's output, with the job id
rs-u-t08-n128-w2.o<job id>.<index>       PBS output, one per node
stdout-<job id>/                         the steps' output
```

## Running it

From this directory on a Derecho login node, with `$PBS_ACCOUNT` set:

```
./submit_runs.sh 8 64 2        # one pair: 2 nodes of 2 waves
./sweep.sh                     # all 24 jobs
./summarize.py                 # as they finish; --nodes for each node
```

`sweep.sh` gives each thread count 8 nodes' worth of one wave, and spreads it
four ways:

| threads | at once | steps | 1 wave  | 2 waves | 4 waves | 8 waves |
| ------- | ------- | ----- | ------- | ------- | ------- | ------- |
| 2       | 64      | 512   | 8 nodes | 4 nodes | 2 nodes | 1 node  |
| 4       | 32      | 256   | 8 nodes | 4 nodes | 2 nodes | 1 node  |
| 8       | 16      | 128   | 8 nodes | 4 nodes | 2 nodes | 1 node  |

Every step does the same work whatever its thread count, so a 2-thread row
holds 4 times the work of an 8-thread row. Compare rows by `ms/step`, not by
run time.

Runs of 1 or 2 nodes go to the `develop` queue and larger ones to `main`:
`develop` runs at most 256 cores (2 nodes) of a user's jobs at once, and job
arrays of at most 4. `QUEUE` overrides this, `WALLTIME` sets the limit per
node (default 10 minutes), `ITERS` the iterations per step (default 40), `DRYRUN=1` writes everything without submitting,
and `THREADS`, `WAVES`, `MAX_NODES` and `PLACEMENTS` narrow the sweep, e.g.
`THREADS=4 PLACEMENTS=unbound ./sweep.sh`.

## How bound steps find their domain

In `../python-regrid` each bound line of the command file names its domain,
which works while all steps start together. With waves, a new step starts
in place of whichever step finished first, so its line's domain may still be
full while another domain has a free place.

Here the command file only says `bound`, and the step chooses its domain when
it starts. `run_step.sh` takes the first free **slot** of its node's
`STEPS_AT_ONCE` slots and runs with `numactl` in domain `slot mod 8`. A slot
is a lock file in node-local `/dev/shm`, held with `flock` for as long as the
step runs. When a step ends its lock is released, and the next step to start
on that node takes that slot, and so that domain. Each array index has its
own set of slots.

`summarize.py` checks this: `dom max` is the most bound steps ever running in
one domain of a node at once, and should equal the steps at once divided by 8.

The same idea could live in `launch_cf`: it knows which slot each step fills,
and could pass it to the step, e.g. as `$LAUNCH_CF_SLOT`, for the command file
to use as `numactl --cpunodebind=$((LAUNCH_CF_SLOT % 8))`.

## What summarize.py reports

| column    | meaning |
| --------- | ------- |
| `nodes`, `waves` | nodes in the job array, and waves per node |
| `ok`      | steps that reported a result, of all steps |
| `comp s`  | the steps' compute phase: mean (slowest) |
| `GB/s`    | each step's estimated memory bandwidth: mean (min – max) |
| `start s` | the rest of a step, mostly starting Python and loading Numba: mean |
| `node-s`  | each node's first step start to last step end, summed over nodes |
| `PBS`     | node time as `launch_cf` reports it, summed: also counts the job's own start |
| `ms/step` | node-s / steps: the cost per step to compare across runs |
| `fill`    | share of the nodes' cores busy with a step during node-s |
| `imbal`   | per node, its time / (its total step time / steps at once): 1.00 when its waves pack perfectly; mean and worst node |
| `dom max` | bound runs: most steps in one domain of a node at once |
| `wall s`  | first start to last end over all nodes; depends also on when PBS started each array index |

## Results

`ITERS=400 WALLTIME=0:30:00 ./sweep.sh`: jobs 8166254 to 8166278, all 24
runs and all 2,688 steps finished. With `ITERS=400` a step computes for
20 to 110 seconds and starts in 1 to 9, so startup no longer decides the
comparison.

### Cost: node-seconds per step

Every step does the same work whatever its threads, so this compares
everything. Columns are nodes x waves per node; lower is better.

| threads | placement | 8 x 1 | 4 x 2 | 2 x 4 | 1 x 8 |
| ------- | --------- | ----- | ----- | ----- | ----- |
| 2       | unbound   | 2.49  | 1.80  | 1.88  | 1.56  |
| 2       | bound     | 1.40  | 1.40  | 1.37  | 1.37  |
| 4       | unbound   | 2.06  | 2.02  | 2.14  | 2.06  |
| 4       | bound     | 1.51  | 1.45  | 1.39  | 1.37  |
| 8       | unbound   | 2.13  | 2.10  | 2.24  | 2.13  |
| 8       | bound     | 1.49  | 1.41  | 1.47  | 1.40  |

**Binding is the big win.** Bound steps cost 1.37 to 1.51 node-seconds,
unbound 1.56 to 2.49: unbound costs 14% to 79% more, and 40% to 55% more in
most cells.

**With binding, threads per step hardly matter.** At 8 waves, 2, 4 and 8
threads cost 1.37, 1.37 and 1.40. Each bound step's bandwidth grows with its
threads (5, 10 and 20 GB/s), and the node as a whole moves about 300 GB/s in
every case: the node's memory is the limit, not the cores. So choose threads
per step for other reasons, such as each step's memory or how many steps
you have.

**With binding, waves change nothing either.** Every bound run kept its
cores 98 to 99% busy, with imbalance 1.01 to 1.02, and step times within a
few percent of each other. The 8-node, 1-wave runs cost up to 10% more,
because each extra node pays its own cold start. The slots worked in every
bound run: `dom max` always equalled the steps at once / 8, and no step
fell back to running unbound.

### Unbound runs and waves

| threads | waves | fill | imbal (worst node) | comp s: mean (slowest) | node GB/s |
| ------- | ----- | ---- | ------------------ | ---------------------- | --------- |
| 2       | 1     | 77%  | 1.36               | 112 (162)              | 171       |
| 2       | 8     | 97%  | 1.03               | 94 (201)               | 272       |
| 4       | 1     | 87%  | 1.25               | 53 (70)                | 208       |
| 4       | 8     | 97%  | 1.03               | 61 (130)               | 206       |
| 8       | 1     | 93%  | 1.12               | 27 (31)                | 200       |
| 8       | 8     | 97%  | 1.03               | 31 (52)                | 200       |
| bound, any | any | 98-99% | 1.01-1.03       | 2 thr 84, 4 thr 41, 8 thr 21 | 280-310 |

Unbound steps vary a lot: the slowest step of a run takes up to 2.6 times
the mean. Waves do even this out at the node level, as hoped: since
`launch_cf` starts a step as soon as any step ends, short steps fill in
behind long ones, and at 8 waves each node is 97% busy whatever the threads.

But the time saved is mostly lost again, because unbound steps compute more
slowly when they start in the middle of a running node than when all start
together (mean compute 27 s rising to 31 s at 8 threads, 53 s to 61 s at 4).
Only at 2 threads did waves pay off clearly, 2.49 down to 1.56 node-seconds,
and mostly because the 1-wave run started so badly: 64 steps starting
together on a cold node took 9 seconds just to start, and left the node 23%
idle. Even then binding was 12% cheaper.

So: if you can bind, bind, and then threads and waves are yours to choose.
If you can't, many small steps in several waves are the least bad choice.

### Wall time is not cost

`wall s` shows that an 8-node array does not always run on 8 nodes at once.
In the unbound 4-thread, 1-wave run PBS ran indices 0, 2, 3 and 4 one after
another on the same node, so the run took 980 seconds of wall time for about 65
seconds per node. What is charged is the node time, not the wall time.

### First tests

Before the sweep, two short runs used the default `ITERS=40`:
`./submit_runs.sh 8 32` (one node, jobs 8165936/7) and `./submit_runs.sh 8 64 2`
(2 nodes, jobs 8166072/3). There the bound run of the second pair landed on
the two nodes the unbound run had just used, with Python and Numba still in
memory, and started its steps in 0.87 s instead of 3.25 s, which halved its
cost per step against 2-second steps. That is why the sweep uses `ITERS=400`.
