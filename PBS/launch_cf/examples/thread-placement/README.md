# Where Do My Threads Run? Thread Placement with `launch_cf`

When you run several multi-threaded programs on one node, Linux decides which
cores their threads run on, and it doesn't always decide well. This example
runs the same small OpenMP program three ways on Derecho and shows exactly
where every thread landed:

1. **Plain:** no placement settings at all.
2. **`numactl`:** each program is kept inside its own NUMA domain.
3. **`numactl` + OpenMP binding:** as 2, and each thread also gets a core of
   its own.

The program does no real work, so this example shows *where* threads run, not
how fast. For what placement does to speed, see
[`../numa-python`](../numa-python).

## A few terms

- **Node:** one computer in the cluster. A Derecho CPU node has 2 AMD EPYC
  processors with 64 cores each, so **128 cores**.
- **Hardware thread:** each core can run 2 threads at once, so Linux sees
  **256 CPUs**, numbered 0–255. CPU *c* and CPU *c* + 128 are the two halves of
  the same physical core: CPU 3 and CPU 131 are both core 3. Two busy threads on
  one core share it, and each runs slower than it would alone.
- **NUMA domain:** the 128 cores are split into **8 groups of 16**, each with
  its own memory attached. A core reads its own domain's memory fastest.

  | domain | cores (first CPU) | second CPU of the same cores |
  | ------ | ----------------- | ---------------------------- |
  | 0      | 0–15              | 128–143                      |
  | 1      | 16–31             | 144–159                      |
  | 2      | 32–47             | 160–175                      |
  | 3      | 48–63             | 176–191                      |
  | 4      | 64–79             | 192–207                      |
  | 5      | 80–95             | 208–223                      |
  | 6      | 96–111            | 224–239                      |
  | 7      | 112–127           | 240–255                      |

  This comes from [`lscpu.txt`](lscpu.txt), the output of `lscpu` on a
  Derecho compute node.
- **Step:** one line of a `launch_cf` command file, run as its own program.
- **OpenMP thread:** one of the threads an OpenMP program starts.
  `OMP_NUM_THREADS` sets how many.

## The setup

Each step runs [`../hello_omp.exe`](../hello_omp.cpp) with 16 OpenMP threads.
Every thread prints one line saying which CPU it is on:

```
step 1 | host dec0093 | core 248 | thread 0 of 16 | PBS_ARRAY_INDEX=0
```

(The program says "core", but the number is the CPU number from the table
above, so 248 is the second hardware thread of core 120.)

There are 16 steps. `launch_cf --nthreads 16 --steps-per-node 8` puts 8 steps
on each node, 8 × 16 = 128 threads for 128 cores, so it needs 2 nodes. It
submits them as a PBS job array with indices 0 and 1, one node each. Steps 1–8
run on index 0, and steps 9–16 on index 1.

The three command files are the same except for what comes before
`../hello_omp.exe` on each line:

| command file            | a line of it                                                                              |
| ----------------------- | ----------------------------------------------------------------------------------------- |
| `cmdfile`               | `../hello_omp.exe 4`                                                                      |
| `cmdfile.numactl`       | `numactl --cpunodebind=3 --membind=3 ../hello_omp.exe 4`                                  |
| `cmdfile.numactl_bind`  | `OMP_PROC_BIND=close OMP_PLACES=cores numactl --cpunodebind=3 --membind=3 ../hello_omp.exe 4` |

What the additions do:

- `numactl --cpunodebind=3` lets the program run only on domain 3's CPUs, and
  `--membind=3` makes it take its memory only from domain 3. The domain number
  counts 0 to 7 down the file and starts over, so the 8 steps on a node get one
  domain each.
- `OMP_PLACES=cores` tells OpenMP to treat each physical core as one place
  to put a thread, and `OMP_PROC_BIND=close` to put thread 0 on the first core
  it may use, thread 1 on the next, and so on, and keep each thread there.
  Combined with `numactl`, step 4's thread *i* runs on core 48 + *i*.

## Running it

From the `examples` directory, build the program first:

```
cd PBS/launch_cf/examples
make hello_omp.exe
```

Then from this directory, with `$PBS_ACCOUNT` set to your project code,
submit all three. Each takes a few seconds once it starts:

```
cd thread-placement
./submit_launch_cf.sh
./submit_launch_cf_numactl.sh
./submit_launch_cf_numactl_bind.sh
```

Each run writes its steps' output to `stdout-<job id>/step-NNNNN.out`, and
`launch_cf.o<job id>.<index>` logs what each node launched. Look at one step
with `cat stdout-<job id>/step-00001.out`.

To summarize a whole run, use [`../parse_steps.py`](../parse_steps.py) with
the `lscpu.txt` here, so that it can map CPUs to cores and domains:

```
python3 ../parse_steps.py stdout-<job id> --lscpu lscpu.txt -o steps.csv
```

Add `--details` to list which cores took more than one thread.

## Results

These are from one run of each on Derecho.

### Plain: threads spread all over the node

Step 1's 16 threads, sorted by thread number:

```
step 1 | host dec0093 | core 248 | thread 0 of 16 | PBS_ARRAY_INDEX=0
step 1 | host dec0093 | core 183 | thread 1 of 16 | PBS_ARRAY_INDEX=0
step 1 | host dec0093 | core 32 | thread 2 of 16 | PBS_ARRAY_INDEX=0
step 1 | host dec0093 | core 215 | thread 3 of 16 | PBS_ARRAY_INDEX=0
...
step 1 | host dec0093 | core 48 | thread 14 of 16 | PBS_ARRAY_INDEX=0
step 1 | host dec0093 | core 219 | thread 15 of 16 | PBS_ARRAY_INDEX=0
```

Those CPUs are in 6 different domains. If this program used memory, most of
its threads would be reading it from another domain.

### `numactl`: each step in its own domain

```
step 1 | host dec0906 | core 130 | thread 0 of 16 | PBS_ARRAY_INDEX=0
step 1 | host dec0906 | core 143 | thread 1 of 16 | PBS_ARRAY_INDEX=0
step 1 | host dec0906 | core 131 | thread 2 of 16 | PBS_ARRAY_INDEX=0
...
step 1 | host dec0906 | core 0 | thread 14 of 16 | PBS_ARRAY_INDEX=0
step 1 | host dec0906 | core 136 | thread 15 of 16 | PBS_ARRAY_INDEX=0
```

Every CPU is in domain 0 (0–15 or 128–143), but the order is random: the
scheduler still chooses which core in the domain each thread uses.

### `numactl` + OpenMP binding: one thread per core, in order

```
step 1 | host dec1965 | core 128 | thread 0 of 16 | PBS_ARRAY_INDEX=0
step 1 | host dec1965 | core 1 | thread 1 of 16 | PBS_ARRAY_INDEX=0
step 1 | host dec1965 | core 2 | thread 2 of 16 | PBS_ARRAY_INDEX=0
...
step 1 | host dec1965 | core 14 | thread 14 of 16 | PBS_ARRAY_INDEX=0
step 1 | host dec1965 | core 15 | thread 15 of 16 | PBS_ARRAY_INDEX=0
```

Thread *i* is on core *i*. Thread 0 reported CPU 128, which is the second
hardware thread of core 0: OpenMP binds a thread to a whole core, and either
half of it is fine.

### The whole node

`parse_steps.py` on each run. `1-dom` is how many of the node's 8 steps kept
all their threads in one domain, and `max dom` is the most domains any one
step was spread over. `reused` counts physical cores that took two or more
threads, and `unused` those that took none.

| run              | index | node    | 1-dom | max dom | cores used | reused | unused |
| ---------------- | ----- | ------- | ----- | ------- | ---------- | ------ | ------ |
| plain            | 0     | dec0093 | 0 / 8 | 8       | 121        | 7      | 7      |
| plain            | 1     | dec0840 | 0 / 8 | 7       | 111        | 15     | 17     |
| `numactl`        | 0     | dec0906 | 8 / 8 | 1       | 127        | 1      | 1      |
| `numactl`        | 1     | dec1214 | 8 / 8 | 1       | 128        | 0      | 0      |
| `numactl` + bind | 0     | dec1965 | 8 / 8 | 1       | 128        | 0      | 0      |
| `numactl` + bind | 1     | dec2005 | 8 / 8 | 1       | 128        | 0      | 0      |

- **Plain:** not one step stayed in one domain. Every step was spread over 6
  to 8 of them. On the second node, 15 cores ran two threads at once
  while 17 cores ran none.
- **`numactl`:** every step stayed in its own domain. Inside the domain the
  scheduler still chose the cores: on the first node, step 3 put two
  threads on core 40 and none on core 46.
- **`numactl` + binding:** every step in its own domain, and every thread on
  a core of its own, in the same order every time.

Plain and `numactl` placement change from run to run, so your numbers will
differ. Bound placement should come out the same every time.

## Which should I use?

- **Several threaded steps per node:** use `numactl --cpunodebind=d
  --membind=d`, with one domain per step. It keeps each step's threads near
  their memory, and it works for any program: OpenMP, Python, or anything
  else.
- **OpenMP programs:** also set `OMP_PROC_BIND=close OMP_PLACES=cores`. It
  costs nothing and makes placement predictable. These variables only affect
  OpenMP; Python threads, for example, ignore them.
- **Size steps to fit domains:** 16 threads per step and 8 steps per node
  fits Derecho exactly. Other combinations work too, for example 32 threads
  over two domains with `--cpunodebind=0,1 --membind=0,1` and 4 steps per node.
  A step that doesn't fill whole domains is harder to place well.

How much any of this speeds up a real program depends on the program.
Programs that spend their time reading large arrays from memory benefit the
most: in [`../numa-python`](../numa-python), `numactl` made threaded NumPy
steps twice as fast.

## Troubleshooting

**Check a step's output, not just the job log.** `launch_cf.o*` reports
`Done` for each node even if every step failed. If you forget to build
`hello_omp.exe`, each `step-*.out` says

```
numactl: execution of `../hello_omp.exe': No such file or directory
```

while the job log looks normal.

**Remember that paths are relative to this directory.** Steps run from the
directory you submitted from, which is why the command files say
`../hello_omp.exe`.
