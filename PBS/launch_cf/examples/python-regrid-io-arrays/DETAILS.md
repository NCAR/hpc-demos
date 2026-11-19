# Job Array Shape and the Queue: Measurements

This file reports two sets, submitted on 16 November 2026 to `main` at
regular priority, as `./summarize.py` reports them. Each set is seven runs of
the same 1024 files, submitted within a second of each other in a random
order.

## How Derecho orders the queue

The scheduler sorts queued jobs by

```
priority = boost + scale × (500 × fairshare + 300 × eligible time / 24 h)
```

There is no term for the number of nodes, and a queued job array is one
entry in line, whatever its size. So every run of a set enters with the same
priority, and gains priority at the same rate while it waits. Among jobs of
equal priority, the scheduler considers the earlier job id first. Whether a
job can start then depends on whether its nodes are free, or can be used
before a higher job needs them (backfill).

`pbs-prio` reports each queued job's computed priority and place in line from
a cache that CISL refreshes every few minutes, so consecutive samples may be
the same. Note that `qstat -f -t -x -F json` of a finished job array puts a
line `qstat: Unknown Job Id N` into its JSON, and `summarize.py` strips it.

## Set s1 (jobs 8209412–8209418)

Every step failed at once, because `calc_anomaly_numba_pario.py` was missing
an import. The jobs still queued and started normally, so their queue data is
valid, but their run times and costs are not.

| nodes | waves | wall | prio first | prio max | place first | place best | wait first s | wait median s | wait last s |
| ----: | ----: | ---- | ---------: | -------: | ----------: | ---------: | -----------: | ------------: | ----------: |
| 64 | 1  | 0:10 | 129.93 | 130.21 | 247 | 239 |  94 | 256 | 287 |
| 32 | 2  | 0:10 | 129.93 | 130.88 | 249 | 233 | 303 | 321 | 334 |
| 16 | 4  | 0:10 | 129.93 | 130.88 | 248 | 232 | 287 | 294 | 303 |
| 8  | 8  | 0:10 | 129.93 | 130.88 | 250 | 234 | 334 | 337 | 337 |
| 4  | 16 | 0:15 | 129.93 | 130.22 | 244 | 236 | 110 | 162 | 163 |
| 2  | 32 | 0:20 | 129.93 | 130.45 | 245 | 232 | 162 | 172 | 183 |
| 1  | 64 | 0:30 | 129.93 | 131.53 | 246 | 230 | 503 | 503 | 503 |

The 64-node array's first node started first, after 94 s, though its job id
was the fourth of the set. The 1-node job, with the longest wall-time request,
waited longest, 503 s.

## Set s2 (jobs 8209513–8209519)

All 1024 steps of every run succeeded.

| nodes | waves | wall | prio first | prio max | wait first s | wait median s | wait last s | done s | node-s | run s |
| ----: | ----: | ---- | ---------: | -------: | -----------: | ------------: | ----------: | -----: | -----: | ----: |
| 64 | 1  | 0:10 | 130.14 | 132.24 |  659 |  798 |  994 | **1015** | 1366 | 356 |
| 32 | 2  | 0:10 | 130.14 | 133.57 | 1070 | 1261 | 1275 | 1370 | 2064 | 300 |
| 16 | 4  | 0:10 | 130.14 | 134.48 | 1320 | 1352 | 1510 | 1575 | 1379 | 255 |
| 8  | 8  | 0:10 | 130.14 | 133.57 | 1042 | 1052 | 1052 | 1251 | 1397 | 209 |
| 4  | 16 | 0:15 | 130.14 | 133.57 | 1052 | 1062 | 1070 | 1407 | 1218 | 355 |
| 2  | 32 | 0:20 | 130.14 | 133.37 | 1026 | 1032 | 1039 | 1552 | 1012 | 526 |
| 1  | 64 | 0:30 | 130.14 | 133.37 | 1011 | 1011 | 1011 | 1900 | **881** | 889 |

`done s` is the time from submission to the end of the last node. `node-s`
is the node time used, summed over the nodes. `run s` is the time from the
first node's start to the last node's end.

- **The runs started in job-id order**, 8209513 (64 nodes) first and 8209519
  (16 nodes) last, as equal priority predicts. In s1 they did not, so with
  two sets, which shape starts first is not settled.
- **Wide arrays start their nodes over minutes.** The nodes of the 64-, 32-
  and 16-node arrays started over 335, 205 and 190 s. The nodes of arrays of
  8 nodes or fewer started within 20 s of each other. An array's nodes don't have to
  start together, which is what lets a wide array start at all on a busy
  system.
- **The narrowest jobs cost least.** They used 881 node-seconds on 1 node, 1,012 on 2
  and 1,218 on 4, against 1,366 to 1,397 on 8 to 64 nodes. The 32-node run
  cost 2,064, and we don't know why.

One set costs about 9,300 node-seconds, or 330 core-hours.
