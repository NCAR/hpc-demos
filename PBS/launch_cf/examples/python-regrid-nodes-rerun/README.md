# Choosing the Number of Nodes, and Finishing Work on the Preempt Queue

This example uses the threaded Python calculation of
[`../python-regrid`](../python-regrid) to show two `launch_cf` options, and a
cheap way to run with them:

- **`--nodes N`** spreads the steps of a command file over *N* nodes.
  `launch_cf` works out how many steps each node gets.
- **The `preempt` queue** runs jobs on nodes that would otherwise be idle, at
  **one fifth of the usual charge**. In return, PBS can take a node back at
  any time and end the job on it.
- **`--rerun JOBID`** submits again only the steps of a finished job that did
  not succeed: those cut short, those that never started, and those that
  failed.

Together, the last two let you get a lot of work done for little of your
allocation. If you have a small allocation, such as an exploratory one, this
is a good way to make it last. See [Running on the preempt queue](#running-on-the-preempt-queue).

> `--nodes` and `--rerun` are new, and not yet in the `launch_cf` installed on
> Derecho. The scripts here put a development copy (the
> `launch_cf-multiple-waves` branch of
> [NCAR/pbstools](https://github.com/NCAR/pbstools)) first in `PATH`.

## The steps

Each step is one run of [`calc_anomaly_numba.py`](calc_anomaly_numba.py), the
memory-bound stencil calculation described in
[`../python-regrid`](../python-regrid#the-calculation). Each step runs 8
threads, and `numactl` keeps it in one of the node's 8 NUMA domains, so a
node runs 16 steps at once, 2 in each domain:

```
OMP_NUM_THREADS=8 numactl --cpunodebind=0 --membind=0 ./run_step.sh 1 40
```

The last number is how many iterations the step computes, which sets how long
it takes: about 0.05 seconds each when a node runs 16 steps at once.
[`generate_runs.sh`](generate_runs.sh) writes three command files:

| command file     | steps | iterations | each step takes | used for |
| ---------------- | ----- | ---------- | --------------- | -------- |
| `cmdfile.short`  | 32    | 40         | a few seconds   | `--nodes` |
| `cmdfile.medium` | 32    | 2000       | about 2 minutes | trying `--rerun` on the develop queue |
| `cmdfile.long`   | 256   | 6000       | about 5 minutes | the preempt queue and `--rerun` |

| file                      | role |
| ------------------------- | ---- |
| `generate_runs.sh`        | writes the three command files |
| `dryrun_nodes.sh`         | shows how `--nodes` lays out `cmdfile.short`, submitting nothing |
| `submit_nodes.sh N`       | runs `cmdfile.short` on *N* nodes of the develop queue |
| `submit_develop_rerun.sh` | runs `cmdfile.medium` on 2 develop nodes; given a job id, reruns what did not succeed |
| `submit_preempt.sh`       | runs `cmdfile.long` on 4 nodes of the preempt queue |
| `rerun_preempt.sh JOBID`  | reruns, on the preempt queue, the steps of that job that did not succeed |
| `run_step.sh`             | one step: `calc_anomaly_numba.py` under `/usr/bin/time` |
| `config_env.sh`           | sourced on the compute node: the `npl-2026a` conda environment, and Numba's OpenMP threading layer |

Start from this directory on a Derecho login node, with `$PBS_ACCOUNT` set to
your project code:

```
./generate_runs.sh
```

## `--nodes`: say how many nodes, not how many steps per node

Without `--nodes`, you tell `launch_cf` how many steps each node runs, with
`--steps-per-node`, and it asks for as many nodes as that takes. With
`--nodes N`, you say how many nodes you want, and `launch_cf` divides the
steps among them, rounding up. You give one or the other, not both.

Each node is one element of a PBS job array, and runs its steps 16 at a time.
If a node gets more steps than run at once, it starts the next as soon as one
finishes, in "waves".

`./dryrun_nodes.sh` asks `launch_cf --dryrun` what it would submit for the 32
steps of `cmdfile.short` on 1, 2, 3, 5 and 40 nodes. It submits nothing, so it
costs nothing:

| `--nodes` | steps per node | at once | waves | array elements | note |
| --------- | -------------- | ------- | ----- | -------------- | ---- |
| 1         | 32             | 16      | 2     | none: one job  | |
| 2         | 16             | 16      | 1     | 0-1            | |
| 3         | 11             | 11      | 1     | 0-2            | the last node gets 10 |
| 5         | 7              | 7       | 1     | 0-4            | the last node gets 4 |
| 40        | 1              | 1       | 1     | 0-31           | "32 steps at 1 steps / node need only 32 of the 40 nodes requested" |

Things to notice:

- **Every node is a whole node**, charged in full, even one that runs 7 steps
  on 56 of its 128 cores. Pick a node count that fills the nodes: here 1 or 2.
- **More steps than fit don't need more nodes.** `--nodes 1` runs all 32 on
  one node, in two waves. It takes longer, but uses no more node time, and a
  1-node job often starts sooner.
- **With `numactl`, uneven counts leave uneven domains.** With 11 steps on a
  node, 3 of its domains run 2 steps and 5 run 1.

Then run three of them for real on the develop queue:

```
./submit_nodes.sh 1
./submit_nodes.sh 2
./submit_nodes.sh 3
```

On 13 November 2026 all 32 steps of each succeeded. With 3 nodes, steps 1-11,
12-22 and 23-32 ran on three different nodes. Each node took 4 to 12 seconds;
most of that is starting Python (see [`../python-regrid`](../python-regrid#starting-up-is-a-big-part-of-a-short-step)).

## Running on the preempt queue

Derecho's `preempt` queue (see the
[NCAR documentation](https://ncar-hpc-docs.readthedocs.io/en/latest/pbs/preemption/)):

- **runs a job only on nodes that would otherwise sit idle**, so you can't
  know when it will start; it may wait a long time when Derecho is busy;
- **charges 0.2 of the usual rate**: a node-hour costs 25.6 core-hours instead
  of 128;
- **can take a node back** when a job from another queue needs it. The job
  then gets a signal to stop, and is killed 10 minutes later if it hasn't. On
  Derecho, PBS then deletes it: it is not put back in the queue to run again.

Losing a node in the middle of a job sounds bad, but `launch_cf` jobs suit
the preempt queue well:

- **Each node is its own job** (an element of the job array), so losing one
  node doesn't touch the others.
- **Each step is independent**, so a node taken back loses only the steps it
  was running and those it hadn't started. Every step that finished is done.
- **`--rerun` finds the steps that didn't finish** and submits just those.

So a job on the preempt queue, followed by reruns until nothing is left,
gets all the work done at about a fifth of the cost. The main thing you give
up is knowing when it will finish.

```
./submit_preempt.sh
```

runs the 256 steps of `cmdfile.long` on 4 nodes: 64 steps per node, in 4
waves of 16. A step takes about 5 minutes, so each node needs about 22
minutes, and the job asks for an hour. The whole job uses about 1.4
node-hours: about 37 core-hours on the preempt queue, against 185 on `main`.

When the job has finished (`qstat` no longer lists it), see what's left:

```
./rerun_preempt.sh <job id>
```

If every step succeeded, `launch_cf` says so and submits nothing. Otherwise it
lists the steps that didn't succeed and why, writes them to
`cmdfile.long.<job id>.rerun`, and submits that, again on the preempt queue.
Repeat with each new job id until there is nothing left to rerun.

`rerun_preempt.sh` uses `--steps-per-node 16`: whatever number of steps is
left, each node runs 16, all at once, on as many nodes as that needs.
`--rerun` does not take the earlier job's options, so you choose the layout
again for what's left.

On 13 November 2026, job 8179906 waited in the queue for an hour and a half
(submitted at 15:30, its nodes started between 17:02 and 17:06), while about
1,200 jobs were waiting for `main`. Each of its 4 nodes then ran its 64 steps
in 21.6 to 21.7 minutes, and each step computed for 307 to 328 seconds. No
node was taken back, so all 256 steps succeeded:

```
$ ./rerun_preempt.sh 8179906
All 256 steps of job 8179906 succeeded; there is nothing to rerun.
```

The 1.44 node-hours were charged about 37 core-hours, where `main` would
have charged 185.

Whether a job loses nodes depends on how busy Derecho is while it runs, so
yours may. The next section shows what `--rerun` does then.

### Try `--rerun` without waiting for a preemption

A job may well finish on the preempt queue without losing a node. To see what
`--rerun` does, take a node back yourself, on the develop queue:

```
./submit_develop_rerun.sh            # 32 steps of about 2 minutes, on 2 nodes
qdel '<job id>[1]'                   # while it runs: end the second node's job
./submit_develop_rerun.sh <job id>   # when the job has finished
```

`qdel` of one array element is what a preemption does to it. On 13 November
2026, deleting element 1 about a minute into its steps gave:

```
Job 8179847: 16 of 32 steps did not succeed:
  step 17 of job 8179847: cut short: subjob 1 stopped while it ran
  step 18 of job 8179847: cut short: subjob 1 stopped while it ran
  ...
  ... and 6 more
Wrote ./cmdfile.medium.8179847.rerun, to submit as the command file.
```

and the rerun command file has just those 16 steps, each marked with why it
is there:

```
# the 16 steps of job 8179847 that did not succeed, out of 32 in
# .../python-regrid-nodes-rerun/cmdfile.medium
# written by: launch_cf -q develop -l walltime=0:10:00 -A ... --nthreads 8 --nodes 1 --rerun 8179847
# step 17 of job 8179847: cut short: subjob 1 stopped while it ran
step=16; OMP_NUM_THREADS=8 numactl --cpunodebind=0 --membind=0 ./run_step.sh 17 2000
...
```

The rerun, job 8179905, ran the 16 steps on one node in 110 seconds, and all
succeeded. Asking again then gives:

```
$ ./submit_develop_rerun.sh 8179905
All 16 steps of job 8179905 succeeded; there is nothing to rerun.
```

Note that the rerun's step logs are numbered by their place in the rerun
command file: `stdout-8179905.desched1/step-00001.out` holds the output of
member 17, which was step 17 of the first job. Each step's own output says
which member it is.

## Using this with your own work

- **Run `--rerun` from the directory you submitted from.** It reads the job's
  PBS output files (`launch_cf.o<job id>.<element>`) and its step logs there.
  Don't delete them, or edit the command file, until everything has run.
- **Make steps safe to run twice.** A step cut short may have written part of
  its output. When it reruns, it should start over or carry on from where it
  stopped, not trip over what it left behind.
- **Shorter steps lose less.** A node taken back loses the steps it was
  running. Steps of minutes rather than hours keep that loss small.
- **A step can use its 10 minutes.** PBS signals the job with `SIGTERM` 10
  minutes before killing it. As written, these steps simply stop. A step that
  catches `SIGTERM` can save its work first: see [`../../../preempt`](../../../preempt)
  for examples in C, C++, Bash and Python.
- **Keep reruns balanced.** Each rerun step keeps its line from the command
  file, including its `numactl` domain. The steps a node was running when it
  was taken back are spread evenly over the domains, so this works out here;
  check it if you pick steps to rerun by other means.
- **Use the preempt queue when you can wait.** For work you need by a
  deadline, use `main`; for work that can finish whenever, `preempt` costs a
  fifth as much.
