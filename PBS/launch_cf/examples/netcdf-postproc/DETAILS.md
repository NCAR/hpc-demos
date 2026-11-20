# NetCDF Post-Processing: Measurements

This file holds the measurements behind [README.md](README.md), and how to
turn on the monitoring used to get them.

## Optional monitoring

`config_env.sh` is sourced on the compute node, so these must be set there
(uncomment them), not in your login shell:

- `export MEASURE=1` records each operation's peak memory and elapsed time
  under `<outdir>/mem/`.
- `export WATCH_CORES=1` samples, every second, the core each NCO process is
  on (`ps -o psr`) and the cores it is allowed (`Cpus_allowed_list`, which is
  what `taskset` sets). Each step's log gets a summary such as
  `cores: mean/ncra  allowed 0-2  ran on 0,2`. A whole run's placement can be
  counted with:

  ```
  grep -h '^cores:' stdout-<job id>/step-*.out | awk '{print $2, $4}' | sort | uniq -c
  ```

  Each sample costs one `ps` per step, so turn this off for timing runs.

## Results

These runs used Derecho CPU nodes between 2026-10-01 and 2026-10-02.

### The steps are I/O-bound

**First run.** This run processed 128 files of `e5.oper.fc.sfc.minmax`,
parameter `mxtpr`, about 475 MB per file, over the default region, unpinned:

- Every operation used about 0.2 GB at peak (largest 0.21 GB), so a full node
  of 42 steps needed about 23 GB.
- A step took about **10 s** on a full node of 42 steps, but about **3 s** on
  the last node, which ran only 2 steps. The same work ran three times slower
  when 42 steps shared the node. The node had cores to spare (126 processes on
  128 cores), so they weren't the limit; the steps were contending for the
  filesystem.

**The file layout sets the cost.** The inputs are stored in chunks of
`1, 12, 721, 1440`. Each chunk is one whole global field, compressed at
deflate level 1. Reading any region decompresses the whole field, so every operation
pays to read and decompress the entire file whatever region it keeps. Reading
from GLADE is a large share of that cost. In the default-region memory check
(step 3 above), the first operation takes about twice as long as the other two
(2.7 s against 1.3 s), because it reads the file from GLADE and the other two
find it already in memory.

**Global region, pinned against unpinned.** These runs processed 126 files
of `e5.oper.fc.sfc.meanflux`, parameter `msror`, over the whole globe:

- Measured on the login node, the steps needed 0.39, 0.30 and 1.60 GB. `ncks`
  holds the whole region of a variable at once, while `ncra` holds one record.
  That is 2.3 GB per step and 96 GB per node, which fits.
- Steps took about 18.5 s on full nodes. Most of the extra work is `ncks`
  writing out and recompressing the whole field. In the memory check, its time
  rose from 1.3 s for the default region to between 2.8 and 5.6 s for the
  globe; the login-node timings are noisy.
- Pinned and unpinned runs gave the same step times, a mean of 18.53 s
  against 18.56 s (see the `compare_runs.sh` output in
  [README.md](README.md#4-submit-gather-compare)).

### Pinning worked, but had nothing to fix

`WATCH_CORES` showed that `taskset` did what it should. Every pinned process
was allowed only its step's three cores, with each of the 42 blocks used
three times across the run's three nodes. Every unpinned process was allowed
`0-255`.

That also shows the node layout. A Derecho CPU node has **256 logical CPUs,
128 physical cores with two hardware threads each (SMT)**. The second hardware
thread of core *i* is CPU *i*+128.

In the unpinned run, **2316 of 4811 samples (48%) found a process on CPUs
128–255**. The scheduler often put two busy processes on the two hardware
threads of one core while other cores sat idle, and it cost nothing. A
workload limited by its cores would have slowed down. This one didn't, which
is further evidence that the steps spend their time waiting on GLADE.

### Without the filesystem: SMT adds little, pinning slightly hurts

[`smt_test.sh`](smt_test.sh) removes the filesystem. Every process recompresses
the same file at deflate level 6 (5 of its 30 records), reading and writing
`/dev/shm`. That leaves CPU-bound zlib work. It runs 128 processes (one per
physical core) and 256 (two per core), each pinned (`taskset -c i`) and
unpinned. A warm-up run comes first, and each case repeats three times in a
rotated order. The table gives averages of the three repeats on one compute
node:

| placement           | 128 processes | 256 processes | 256 vs 128 |
| ------------------- | ------------- | ------------- | ---------- |
| unpinned            | 34.0 files/s  | 36.1 files/s  | **+6%**    |
| pinned              | 32.3 files/s  | 35.1 files/s  | +9%        |
| pinned vs unpinned  | −5%           | −3%           |            |

- **SMT adds about 6%.** With two processes per core, each process takes
  almost twice as long (median 3.5 s → 6.7 s), so each hardware thread gets
  only a little more than half a core. zlib already keeps a core busy, so a
  second hardware thread has little left to use.
- **Simple pinning was slightly slower in every repeat.** The ranges don't
  overlap (unpinned 33.8–34.2, pinned 31.9–32.7 files/s at 128). It wasn't
  caused by a few busy cores. The pinned processes' median time was slower,
  and the slowest one ran on a different CPU each time. For independent
  single-threaded processes, the Linux scheduler did at least as well as
  pinning each one to a core. We didn't identify the cause of the small
  penalty.
- **Warm up and repeat.** A first single-run version of this test showed
  pinned 30% slower. The first run started 128 NCO processes at once, all
  loading NCO's libraries from GLADE. With a warm-up run excluded, the gap
  shrank to the 3–5% above. Runs this short need a warm-up and repeats.
