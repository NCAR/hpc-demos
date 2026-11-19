# Threads, Job Arrays and Waves: Measurements

This file holds the measurements behind [README.md](README.md): the full
sweep with `--sync-waves`, and the earlier version that placed bound steps
with lock files ("slots") instead.

All runs used Derecho CPU nodes (128 cores, 8 NUMA domains of 16 cores), the
`npl-2026a` conda environment and `ITERS=400`. Each configuration ran once.
Differences under about 0.05 node-seconds per step are within the noise from
Python start-up.

## What summarize.py reports

`summarize.py` takes when each step started and finished from `launch_cf`'s
own PBS output ("launching step", "finished step"), and what each step
computed from its output in `stdout-<job id>/`.

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

## The sweep with `--sync-waves`

Jobs 8169324–8169347 (2, 4 and 8 threads, 12 Nov 2026) and 8176064–8176071
(1 thread, 13 Nov 2026). Every step of every run succeeded.

### Cost: node-seconds per step

Columns are nodes × waves per node; lower is better.

| threads | placement | 8 × 1 | 4 × 2 | 2 × 4 | 1 × 8 |
| ------- | --------- | ----: | ----: | ----: | ----: |
| 1       | unbound   | 2.39  | 1.64  | 1.60  | 1.60  |
| 1       | bound     | 1.41  | 1.39  | 1.36  | 1.36  |
| 2       | unbound   | 2.05  | 1.80  | 1.67  | 1.54  |
| 2       | bound     | 1.52  | 1.45  | 1.39  | 1.36  |
| 4       | unbound   | 1.94  | 1.99  | 2.11  | 2.10  |
| 4       | bound     | 1.40  | 1.48  | 1.41  | 1.38  |
| 8       | unbound   | 1.94  | 1.98  | 2.29  | 2.20  |
| 8       | bound     | 1.73  | 1.42  | 1.45  | 1.45  |

The compute phase alone of a bound step on a full node costs about 1.32
node-seconds, so bound runs come within 3 to 15% of it.

### Bound runs

| threads | compute s, mean (slowest) | GB/s per step | node GB/s | fill |
| ------- | ------------------------- | ------------- | --------- | ---- |
| 1       | 169–170 (172)             | 2.5           | 320       | 98–99% |
| 2       | 84–85 (86–87)             | 5.0           | 320       | 99%  |
| 4       | 42 (43)                   | 10.1          | 322–324   | 97–99% |
| 8       | 21 (22)                   | 20            | 319–322   | 99%  |

- **The node's memory is the limit.** Each step's bandwidth grows with its
  threads, and the node as a whole moves about 320 GB/s in every case.
- **Bound steps take nearly the same time**: within a run, 80% of steps fall
  within about 3% of the median, and the slowest is at most 2.4% over it. So
  waiting for each wave's slowest step costs 1 to 3% of node time.
- **Start-up is the rest.** When 512 two-thread steps start together on 8
  nodes, they take 10.7 s on average to start Python and Numba from the
  shared file system; spread over 8 waves on one node, 1.4 s. That is why
  more waves cost slightly less at 2 threads (1.52 to 1.36).
- **One run lost to start-up.** In the bound 8-thread run on 8 nodes
  (1.73), every step on three of the nodes took about 14 s to start, against
  21 s of compute. The same steps on 4, 2 or 1 nodes cost 1.42 to 1.45.

### Unbound runs

| threads | waves | fill | compute s, mean (slowest) | node GB/s |
| ------- | ----- | ---- | ------------------------- | --------- |
| 1       | 1     | 73%  | 213 (329)                 | 270 (est.) |
| 1       | 8     | 96%  | 190 (581)                 | 307 (est.) |
| 2       | 1     | 81%  | 94 (153)                  | 302       |
| 2       | 8     | 97%  | 93 (200)                  | 307       |
| 4       | 1     | 89%  | 50 (59)                   | 276       |
| 4       | 8     | 97%  | 62 (144)                  | 259       |
| 8       | 1     | 95%  | 27 (31)                   | 252       |
| 8       | 8     | 96%  | 32 (58)                   | 232       |

(1-thread node GB/s is estimated as 128 × the mean step's GB/s.)

Unbound steps vary a lot: the slowest step of a run takes up to 3.3 times
the mean. More waves do even this out at the node level: since `launch_cf` starts
a step as soon as any step ends, short steps fill in behind long ones, and
at 8 waves each node is 96–97% busy. But steps that start on a busy node
compute more slowly than steps that start together, so at 4 and 8 threads
the time gained is lost again. Only at 1 and 2 threads did waves pay off,
mostly because the 1-wave runs started so badly: 512 or 1024 steps starting
together left their nodes 19–27% idle.

### Wall time is not cost

At 2 to 8 threads, 8 waves on one node took 4 to 5.5 times as long as
1 wave on 8 nodes, but used no more node time. What Derecho charges is node time (core-hours), not
wall time. And an 8-node array does not always run on 8 nodes at once: PBS
may run its indices one after another on the same node, as it did with both
indices of the bound 8-thread, 4-wave run.

### Queue wait

All 24 jobs of 12 Nov were submitted within two seconds. The 4- and 8-node
arrays in `main` waited 4 to 8 minutes for nodes. The 1- and 2-node jobs in
`develop` waited up to 38 minutes, but only because `develop` runs at most
2 nodes of one user's jobs at once: PBS's `eligible_time` for them was 2 to
7 seconds. So this sweep says nothing about whether arrays start sooner;
[`../python-regrid-io-arrays`](../python-regrid-io-arrays) looks at that.

### First tests

`./submit_runs.sh 8 32 2` (jobs 8169093, 8169094, the default 40 iterations)
checked that it works: all 32 steps of each ran, and the bound run's PBS
output shows `launch_cf` starting wave 2 only after wave 1 had finished.

## Without synchronized waves: slots

Before `launch_cf` had `--sync-waves`, this sweep was run with a different
way of keeping bound steps on free domains (the `python-regrid-sweep-slotctl`
example, last in
[commit 4c89271](https://github.com/NCAR/hpc-demos/tree/4c89271/PBS/launch_cf/examples/python-regrid-sweep-slotctl)).
Waves were not synchronized: `launch_cf` started a new step as soon as any
finished. The command file said only `bound`, and each step chose its domain
as it started:

- `run_step.sh` took the first free **slot** of its node's `STEPS_AT_ONCE`
  slots, and ran under `numactl` in domain `slot mod 8`.
- A slot was a lock file in node-local `/dev/shm`, held with `flock` for as
  long as the step ran. When a step ended its lock was released, and the next
  step to start on that node took that slot, and so that domain.

This worked: in every bound run the most steps running in one domain at once
was exactly its share, and every node kept its cores 98–99% busy, with
imbalance 1.01–1.03. But it put the placement logic in every step's script.
`launch_cf` knows which slot each step fills, and could pass it to the step
instead; that is proposed in
[NCAR/pbstools#17](https://github.com/NCAR/pbstools/issues/17).

### Results with slots

Jobs 8166254–8166278 (2, 4 and 8 threads, `ITERS=400`), all 2,688 steps
finished. Node-seconds per step:

| threads | placement | 8 × 1 | 4 × 2 | 2 × 4 | 1 × 8 |
| ------- | --------- | ----: | ----: | ----: | ----: |
| 2       | unbound   | 2.49  | 1.80  | 1.88  | 1.56  |
| 2       | bound     | 1.40  | 1.40  | 1.37  | 1.37  |
| 4       | unbound   | 2.06  | 2.02  | 2.14  | 2.06  |
| 4       | bound     | 1.51  | 1.45  | 1.39  | 1.37  |
| 8       | unbound   | 2.13  | 2.10  | 2.24  | 2.13  |
| 8       | bound     | 1.49  | 1.41  | 1.47  | 1.40  |

**Slots and `--sync-waves` cost the same.** Bound runs cost 1.37 to 1.51
node-seconds per step with slots, and 1.36 to 1.52 with `--sync-waves`
(leaving out the one 8-thread run slowed by start-up). Bound steps of this
calculation take nearly the same time, so there is little for slots to gain
by starting each step the moment a domain frees up. Slots should gain more
for steps whose times vary, such as steps that read files; that has not been
measured.

The unbound runs repeat the pattern above: steps vary by up to 2.6 times
the mean, waves raise `fill` to 97%, and only at 2 threads did waves pay off
clearly (2.49 to 1.56).

### A start-up trap

Before the sweep, two short runs used the default `ITERS=40`. There, the
bound run of the second pair landed on the two nodes the unbound run had
just used, with Python and Numba still in memory, and started its steps in
0.87 s instead of 3.25 s, which halved its cost per step against 2-second
steps. That is why the sweeps use `ITERS=400`.
