# NUMA Placement for Threaded Python: Measurements

This file holds the details behind [README.md](README.md). It describes the
computation, gives every result of the single-node trial and of the
`launch_cf` version, and explains how to read a step's output.

## The computation

[`climatology.py`](climatology.py) computes the time mean and standard
deviation, at every grid point, of one month of hourly ERA5 2 m temperature.
The month is 744 × 721 × 1440 float32 values, 3.1 GB, held in memory. The answer is two
721 × 1440 maps. It then computes the same two maps again, many times over,
and throws every copy away. Only the timing matters.

**Why repeat it.** One mean and standard deviation of the month takes about
0.17 s on 16 threads, while reading the file from GLADE takes about 22 s. Done
once, the computing would be too short to measure next to the load, so the
script repeats it. Each repeat is honest work. The array is 50 times the L3
cache of a NUMA domain, so nothing carries over from one repeat to the next,
and every repeat streams all 3.1 GB from memory again. For the memory system,
200 repeats over one month look like one computation over 200 months. The
repeats stand in for heavier analysis.

**What a pass is.** The grid's 721 latitudes are split into 16 bands of about
45, one per thread. A *pass* is one thread computing the mean and standard
deviation of its own band, all 744 hours of it. It reads the band twice, once
to sum it for the mean and once to sum the squared differences from the mean,
8 hours at a time. When all 16 threads have made one pass, the whole month's
mean and standard deviation have been computed once, and 6.2 GB has been read.

**How many passes.** The two parts of the example repeat it differently:

- `numa_test.sh` runs every thread for a fixed **20 s**, as many passes as
  fit. That is about 115 for a process with its threads and memory together,
  and about 70 without. The measure is how much it got through.
- `launch_cf` steps make a fixed **200 passes** per thread (`PASSES` in
  `run_step.sh`). They compute the month's mean and standard deviation 200
  times and read about 1.2 TB. The measure is how long that took.

Three things keep the measurement about memory placement:

- **The threads really run at once.** NumPy releases the GIL inside each call,
  and the script sets `OMP_NUM_THREADS`, `BLIS_NUM_THREADS` and similar
  variables to 1, so its 16 threads are the only threads.
- **The work is limited by memory bandwidth.** A pass does about one
  arithmetic operation per value it reads, so the threads spend their time
  waiting for memory, not computing.
- **Reading the file isn't part of the speed.** The main thread reads the
  whole month before the threads start, and only the passes are timed.
  `numa_test.sh` reads the file once into `/dev/shm` and loads it from there
  for every run; a `launch_cf` step reads it from GLADE and reports that time
  separately.

Each run prints one line. It gives the run's throughput, the NUMA domains its
threads ran on, the domains holding its memory, and `local`, which is the
share of the threads' time spent on the domain that holds their own band. `climatology.py` finds where the
pages are with the `move_pages` system call, and where the threads run with
`sched_getcpu`. [Reading a step's output](#reading-a-steps-output), below, explains
every field.

## Results

One Derecho node (`dec0603`), January 2020 2 m temperature, 3 repeats of 20 s.
The kernel's automatic NUMA balancing was off, so pages stayed where they were
first placed. Node throughput is the sum over the processes; it is the mean of
the three repeats, with the range of single processes beside it.

| case           | node GB/s | range of repeats | per process GB/s | local |
| -------------- | --------- | ---------------- | ---------------- | ----- |
| `8 bind`       | **288.3** | 287.6 – 288.9    | 35.1 – 36.7      | 100%  |
| `8 bind+pin`   | **289.9** | 289.6 – 290.4    | 35.8 – 36.8      | 100%  |
| `8 touch`      | 194.1     | 188.6 – 202.5    | 21.0 – 28.6      | 33%   |
| `8 free`       | 177.4     | 158.3 – 198.8    | 12.0 – 32.2      | 69%   |
| `8 interleave` | 172.6     | 172.5 – 172.9    | 20.3 – 22.9      | 12%   |
| `1 free`       | 38.2      | 37.4 – 39.6      |                  | 33%   |
| `1 bind`       | 36.6      | 36.2 – 37.2      |                  | 100%  |

### Binding to a NUMA domain is worth 1.6 times

With each process bound to its own domain, every process ran at 35–37 GB/s and
the node at 288 GB/s, the same in every repeat. That is about 70% of the node's
peak memory bandwidth (two DDR4-3200 channels, 51 GB/s, per domain). Unbound,
the node averaged 177 GB/s, and single processes ranged from 12 to 32 GB/s.

In a `launch_cf` job that spread matters more than the average. A node is
done only when its slowest step is, and in each repeat the slowest unbound
process ran at 12–18.5 GB/s, a third to a half of the speed of a bound one.

### Unbound, memory piles up in a few domains

The main thread reads the array, so every page of a process lands in the
domain that one thread happened to be on, and its 16 compute threads then
read it from wherever the scheduler puts them. The log shows two costs.

- **Remote reads.** On average 31% of a free process's thread time was spent
  on a domain other than the one holding its data.
- **Shared memory channels.** Eight main threads landing in eight different
  domains would be luck. In every repeat at least one pair of processes had
  their memory in the same domain (two pairs in two of the three), and one or
  two domains held nobody's memory at all. A pair sharing a domain shared its
  bandwidth. In repeat 2, the two processes with memory in domain 3 got 12.0
  and 22.0 GB/s, 34 GB/s together, which is about what one bound process gets
  alone.
  The idle domains' channels went unused.

### Fixes without binding don't hold

- **First touch in each thread (`touch`)** put each band's pages where its
  thread was when it copied the band. But the scheduler then moved the
  threads, so only 33% of thread time stayed local, and the node gained just
  9% over `free`. First touch only keeps memory local if the threads stay
  where they are.
- **Interleaving (`interleave`)** spreads every process's memory evenly over
  all 8 domains, so no domain is overloaded and the result hardly varies, but
  7/8 of all reads are remote. It came out slightly below `free`, at 60% of
  `bind`. (Processes on odd-numbered domains ran at 22.5–22.9 GB/s and those
  on even ones at 20.3–20.6, in every repeat. We didn't find out why.)

### Pinning threads inside the domain adds nothing

`bind+pin` was 0.5% faster than `bind` in every repeat, but that is too
little to matter. Once `numactl` keeps a process's threads and memory in one domain,
where the scheduler puts each thread among those 16 cores doesn't matter. That
agrees with [`../netcdf-postproc`](../netcdf-postproc), where the scheduler
placed independent processes at least as well as pinning did.

### One process alone doesn't show it

On an otherwise idle node, a single unbound process ran at 38 GB/s, slightly
faster than a bound one, though only a third of its thread time was local.
All its memory was in one domain, so it was limited by that domain's two
memory channels however its threads were placed. A placement test with one
process on an idle node would find nothing to fix, as `netcdf-postproc` did;
the effect appears only when every domain is busy.

### Automatic NUMA balancing was off

Linux can fix placement by itself. With automatic NUMA balancing on
(`/proc/sys/kernel/numa_balancing` = 1), the kernel briefly makes a slice of
each process's memory inaccessible, about 256 MB at a time, and learns from
the page faults that follow which domain uses which pages. It then moves
pages to the domain using them, or threads to the domain holding their
memory.

On Derecho it is off (0), and only root can change it. That is usual on HPC
systems, for the reasons in this table:

| | on | off |
| --- | --- | --- |
| **for** | fixes poor placement, such as `free`'s, with no change to the code; follows programs whose access pattern changes | no scanning or page-copying overhead; no jitter in a job whose ranks wait for the slowest; timings repeat |
| **against** | scanning and moving pages cost CPU time even for well-placed processes, and add jitter; slow to act (many seconds to cover a 3 GB array, so little help in a 20 s run); can bounce pages that threads in several domains share, or crowd processes into one domain | poor placement stays poor for the life of the process: placement is the user's job |

So the `free` and `touch` results here are the full cost of poor placement,
with nothing correcting it. With balancing on, they would probably improve
over a long run, and `bind` would not change, because memory bound with
`--membind` is not moved. On a system where it is on, compare the counters
`numa_hint_faults`, `numa_hint_faults_local` and `numa_pages_migrated` in
`/proc/vmstat` before and after a run to see how much it did.

### Conclusions

- For threaded, memory-bound work on a full Derecho node, bind each process
  to one NUMA domain, with `numactl --cpunodebind=d --membind=d`. On this
  workload that gave 1.6 times the throughput and made every process run at
  the same speed.
- Binding the CPUs and the memory together is what matters. Pinning
  individual threads on top of it added nothing.
- Measure placement on a full node. A single process on an idle node shows
  no difference.


## Reading a step's output

Each `stdout-<job id>/step-NNNNN.out` holds what one step wrote, standard
output and standard error together. It has two lines:

```
read VAR_2T(744, 721, 1440) from /glade/campaign/collections/gdex/data/d633000/e5.oper.an.sfc/202001/e5.oper.an.sfc.128_167_2t.ll025sc.2020010100_2020013123.nc
variant=unpinned step=202001 host=dec2443 index=1 cpus=0-255 threads_on=D3:48,D4:19,D7:18,D1:7,D6:3,D5:2,D2:2,D0:1 memory_on=D0:100 local=1 load_s=21.8 seconds=70.9 GBps=17.4 s_per_pass=0.357
```

The first, from `climatology.py` as it starts reading, names the variable,
its shape (time, latitude, longitude) and the file. The second is the step's
report:

| field        | meaning |
| ------------ | ------- |
| `variant`    | the label from the command file: `unpinned` or `pinned` |
| `step`       | the month the step read |
| `host`       | the node it ran on |
| `index`      | `PBS_ARRAY_INDEX`: which array job, so which group of 8 steps shared a node at the same time. A node can serve several indices one after another, as `dec2443` did here |
| `cpus`       | the CPUs the step was allowed. `0-255` is the whole node, both hardware threads of every core: unpinned. A pinned step on domain 3 shows `48-63,176-191`, its 16 cores and their second hardware threads |
| `threads_on` | where the threads ran: after each pass, each thread notes its CPU, and this is the share of those notes in each NUMA domain, largest first. `D0:0` means under 0.5% |
| `memory_on`  | where the data is: the domain of 32 pages sampled through each thread's band (512 in all), found with the `move_pages` system call after the compute phase |
| `local`      | the share of thread time on the domain holding that thread's own band, in %. 100 is ideal; with memory spread evenly over 8 domains it would be about 12 |
| `load_s`     | seconds to read and decompress the file, before computing; not part of `GBps` |
| `seconds`    | the compute phase, from the start (after the 8 steps meet) to when the slowest thread finished its passes |
| `GBps`       | bytes of the array read by all threads together, per second of `seconds`. Each pass reads the band twice |
| `s_per_pass` | seconds one mean and standard deviation of the whole array took at that rate |

So this step's threads ran mostly in domains 3, 4 and 7, while all its
memory sat in domain 0, where its main thread had read the file. Only 1% of
its thread time was local, and it ran at less than half the pinned speed.

`compare_runs.sh` reports each run's step throughput (mean, minimum and
maximum), its mean step time, and `node s`, the time of each node's slowest
step, averaged over nodes. That last is what placement costs a `launch_cf`
job.

## `launch_cf` results

These runs covered 24 months (2019–2020) on 3 nodes per run, unpinned (job
7689807) and pinned (job 7689810). `compare_runs.sh` reports them as follows:

```
run                    steps failed   GB/s    min    max  comp s  node s  local  load s
launch_cf.log             24      0   18.8   14.5   26.3    65.9    76.3   51%    22.2
launch_cf.pinned.log      24      0   36.2   34.6   37.3    33.5    34.4  100%    21.9
```

- **Pinned steps were twice as fast.** They averaged 36.2 GB/s, the same as
  the bound processes of the trial, and the slowest of the 24 still ran at
  34.6. Unpinned steps averaged 18.8 GB/s, and ranged from 14.5 to 26.3.
- **Each node was busy computing 2.2 times longer unpinned.** A node's
  slowest step took 76 s on average unpinned, against 34 s pinned. Pinned,
  the 8 steps on a node finished within about 3 s of each other, most of that
  because February is shorter, so cores hardly sat idle waiting for a
  straggler.
- **Loading cost the same either way**, about 22 s per step to read and
  decompress 3 GB from GLADE. Counting it, a pinned node finished in about
  56 s and an unpinned one in about 98 s.
- **All three unpinned array jobs ran on one node**, `dec2443`, one after
  another; the pinned ones ran on three. A slow node would slow both
  placements alike, and the pinned nodes and the trial's node all gave the
  same 36 GB/s bound, so this is unlikely to matter, but a pinned run on
  `dec2443` would rule it out.

### Why the gap is larger than in the trial

In the trial, unbound processes averaged 22 GB/s (177 GB/s over 8) and were
69% local. Here they averaged 18.8 GB/s and 51%. The difference is not in how
memory was spread. In 23 of the 24 unpinned steps, all of a step's memory was
in one domain, as in the trial. Pairs of steps shared a domain as often or a
little more, and each node left two or three domains holding nobody's
memory.

The difference is what a step waits for. Each thread owns a fixed band, so
**a step with a fixed amount of work is as slow as its slowest thread**. The
other 15 finish their passes and wait. A thread that spends part of the run
on another domain, or sharing a core with another step's thread, holds back
the whole step. In the trial, each thread instead ran for a fixed 20 s, and a
slow thread just did less of the total. The others kept going, so a slow
thread cost only its own share.

The unpinned steps show this. Even the nine whose threads were at least 70%
local averaged only 21 GB/s, against 36 pinned. `201905` had domain 3 to
itself and 77% of its thread time local, and still ran at 16.6 GB/s. Most
threaded codes divide their work this way, including OpenMP's usual static
schedule, so the `launch_cf` result is the one to expect from them. There,
poor placement costs not just bandwidth but also the time every thread
spends waiting for the slowest.

Placement decides not only how fast the average step runs, but how long the
slowest step keeps the node.
