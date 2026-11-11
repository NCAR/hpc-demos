# NUMA Placement for Threaded Python

This example shows a one-line change to a `launch_cf` command file that made
threaded Python analysis of ERA5 data run **twice as fast** on Derecho. It
does not change the Python code at all.

If your steps are threaded, for example NumPy work split over threads, or
dask or xarray with the threaded scheduler, and you run several of them on
each node, put this in front of each step:

```
numactl --cpunodebind=<d> --membind=<d> <your step>
```

with a different domain number *d*, 0 to 7, for each of the 8 steps on a
node. The rest of this README shows why that helps, and how much.

For more placement options, such as pinning each thread to its own core or
spreading memory over all domains, and why they don't help more, see
[`../numa-python-advanced`](../numa-python-advanced).

## Why placement matters

A Derecho CPU node has 128 cores and 256 GB of memory, but it is built as
**8 NUMA domains**, each with 16 cores and its own share of the memory,
about 30 GB. A core
reads memory in its own domain fastest. It can read memory in another domain,
but more slowly, and every domain's memory has only so much bandwidth to
share among the cores reading from it.

Linux doesn't take this into account when it runs ordinary Python:

- A process's memory goes into the domain where the thread that first wrote
  it was running. In a typical script, the main thread reads the whole file,
  so all of the data lands in one domain.
- The scheduler then runs the process's threads on whichever cores are free,
  often in other domains, and moves them around.

With 8 processes on a node, several often end up with their data in the same
domain, sharing its bandwidth, while other domains' memory goes unused.

`numactl` fixes this from outside the program:

- `--cpunodebind=d`: the process and all its threads run only on the 16
  cores of domain *d*.
- `--membind=d`: all its memory comes from domain *d*.

It matters for work that is limited by **memory bandwidth**: reading large
arrays and doing little arithmetic on each value, as means, anomalies,
standard deviations and most other reductions do.

## The computation

[`climatology.py`](climatology.py) computes the time mean and standard
deviation, at every grid point, of one month of hourly ERA5 2 m temperature:
744 × 721 × 1440 float32 values, 3.1 GB, held in memory. The grid's 721
latitudes are split into 16 bands, one per thread, and each thread computes
the mean and standard deviation of its own band with NumPy. NumPy releases the
GIL during each call, so the 16 threads really run at once.

One mean and standard deviation of the month takes only about 0.17 s, much
too short to time next to the 22 s it takes to read the file. So the script
repeats it many times and keeps none of the results. Each repeat reads all
3.1 GB from memory again, so the repeats stand in for heavier analysis.

The script prints one line per run with its speed in GB/s and where its
threads and memory were; see [Reading a step's output](#reading-a-steps-output).

## Part 1: a single-node test

[`numa_test.sh`](numa_test.sh) runs 8 copies of `climatology.py`, 16 threads
each, on one node, as `launch_cf` would run 8 steps. They compute together for
20 seconds, so they compete for memory bandwidth.

| case     | how each process is started                                   |
| -------- | ------------------------------------------------------------- |
| `8 free` | `python3 climatology.py ...`: no placement                    |
| `8 bind` | `numactl --cpunodebind=d --membind=d python3 climatology.py ...`, *d* = 0 to 7 |
| `1 free` | one process alone on the node, no placement                   |

On Derecho, from this directory:

```
qsub -I -A $PBS_ACCOUNT -q main -l select=1:ncpus=128 -l walltime=00:20:00
./numa_test.sh               # 3 repeats of 20 s; or ./numa_test.sh <repeats> <seconds>
```

or as a batch job, `qsub -A $PBS_ACCOUNT numa_test.sh`. The script activates
the `npl-2026a` conda environment if NumPy and netCDF4 aren't already
available, and reads January 2020 from the ERA5 collection on GLADE. Set
`ERA5_MONTH=YYYYMM` for another month, or `SYNTHETIC=744` for random data of
the same shape.

### Results

One Derecho node, 3 repeats of 20 s. Node throughput is the total over the
processes, averaged over the repeats. `local` is the share of the threads'
time spent in the domain that holds their data.

| case     | node GB/s | per process GB/s | local |
| -------- | --------- | ---------------- | ----- |
| `8 bind` | **288**   | 35 – 37          | 100%  |
| `8 free` | 177       | 12 – 32          | 69%   |
| `1 free` | 38        |                  | 33%   |

(These were measured with the advanced version of the script, which ran
these three cases along with others; see
[`../numa-python-advanced`](../numa-python-advanced#results).)

- **Binding gave the node 1.6 times the throughput.** Every bound process ran
  at about the same speed, in every repeat.
- **Unbound, speeds varied widely**, from 12 to 32 GB/s. In every repeat at
  least two processes had their data in the same domain and shared its
  bandwidth, while one or two domains held nobody's data.
- **One process alone shows no problem.** On an otherwise empty node it
  had all the memory bandwidth to itself and ran as fast as a bound process,
  even though only a third of its threads' time was local. A test with one
  process on an idle node would find nothing to fix: the problem appears only
  when the node is full.

## Part 2: the same work as `launch_cf` steps

Here each step reads one month of ERA5 from GLADE and computes its mean and
standard deviation with 16 threads, 200 times over. `launch_cf --nthreads 16
--steps-per-node 8` puts 8 steps on each node. Two command files differ only
in placement:

```
# cmdfile: free
./run_step.sh free .../e5.oper.an.sfc.128_167_2t.ll025sc.2019010100_2019013123.nc

# cmdfile.bind: bound
numactl --cpunodebind=0 --membind=0 ./run_step.sh bind .../e5.oper.an.sfc.128_167_2t.ll025sc.2019010100_2019013123.nc
```

`launch_cf` gives each node a block of 8 consecutive lines of the command file,
so the domain number in `cmdfile.bind` just counts 0 to 7 and starts over
(see [`../gen_cmdfile_numactl.sh`](../gen_cmdfile_numactl.sh)).

| file                       | role                                              |
| -------------------------- | ------------------------------------------------- |
| `gen_cmdfile_numa.sh`      | write `cmdfile` or, with `bind`, `cmdfile.bind`   |
| `run_step.sh`              | one step: `climatology.py` on one month           |
| `config_env.sh`            | sourced on the compute node: activates `npl-2026a`|
| `submit_launch_cf.sh`      | submit the free run                               |
| `submit_launch_cf_bind.sh` | submit the bound run                              |
| `compare_runs.sh`          | compare the two runs                              |

From this directory on a Derecho login node, with `$PBS_ACCOUNT` set:

```
./gen_cmdfile_numa.sh            # 24 months from January 2019 -> cmdfile
./gen_cmdfile_numa.sh bind       #                              -> cmdfile.bind
./submit_launch_cf.sh
./submit_launch_cf_bind.sh
./compare_runs.sh                # once both have finished
```

`START=YYYYMM` and `NSTEPS` choose other months. `NSTEPS` must be a multiple
of 8: after loading, the 8 steps on a node wait for each other and start
computing together, so that they compete for memory as steps of a real job
would.

### Results

24 months (2019–2020), 3 nodes per run:

|                                 | free        | bind        |
| ------------------------------- | ----------- | ----------- |
| step speed, GB/s (min – max)    | 18.8 (14.5 – 26.3) | **36.2** (34.6 – 37.3) |
| slowest step per node, s        | 76          | **34**      |
| local                           | 51%         | 100%        |
| reading the file, s             | 22          | 22          |

- **Bound steps were twice as fast**, and all ran at nearly the same speed.
- **Each node finished its computing 2.2 times sooner.** A node is busy until
  its slowest step finishes, so the slowest step is what costs core-hours.
  Counting the time to read the file, a bound node finished in about 56 s and
  a free one in about 98 s.
- **Reading the file took the same time either way.** Placement speeds up
  computing on data in memory, not reading from GLADE.
- **Free runs vary.** A second pair of runs gave 23.4 GB/s free against the
  same 36.2 GB/s bound, and bound nodes finished computing 1.9 times sooner.

The gap is larger here than in Part 1 because each step has a fixed amount
of work, divided equally among its threads. A step is only as fast as its
slowest thread, so one thread running far from its data holds back the
other 15.

## Using this with your own work

- **Match threads to the domain.** 16 threads per step, 8 steps per node, is
  one step per domain. Tell your code to use 16 threads (for example
  `dask.config.set(num_workers=16)`), and run `launch_cf` with
  `--nthreads 16 --steps-per-node 8`.
- **Stay within a domain's memory.** With `--membind`, a step can only use its
  domain's memory, about 30 GB. A step that needs more can fail rather than
  spill into other domains; give it two domains,
  `--cpunodebind=0,1 --membind=0,1`, and run 4 steps per node instead.
- **Only memory-bound work benefits much.** Work that is mostly reading files,
  or mostly heavy arithmetic, won't speed up much.

## Reading a step's output

Each `stdout-<job id>/step-NNNNN.out` ends with a line like

```
variant=free step=202001 host=dec2443 index=1 cpus=0-255 threads_on=D3:48,D4:19,D7:18,D1:7,D6:3,D5:2,D2:2,D0:1 memory_on=D0:100 local=1 load_s=21.8 seconds=70.9 GBps=17.4 s_per_pass=0.357
```

| field        | meaning |
| ------------ | ------- |
| `variant`    | `free` or `bind`, from the command file |
| `step`       | the month the step read |
| `host`       | the node it ran on |
| `index`      | which array job of the `launch_cf` run, so which group of 8 steps shared a node |
| `cpus`       | the CPUs the step was allowed: `0-255` is the whole node (free); a bound step on domain 3 shows `48-63,176-191` |
| `threads_on` | the share of the threads' time on each NUMA domain, largest first |
| `memory_on`  | the share of the step's data held in each domain |
| `local`      | the share of the threads' time spent in the domain holding their data, in %. 100 is ideal |
| `load_s`     | seconds to read the file, not counted in `GBps` |
| `seconds`    | the compute time, until the slowest thread finished |
| `GBps`       | data read from memory per second, all threads together |
| `s_per_pass` | seconds for one mean and standard deviation of the month at that speed |

This free step's threads ran mostly in domains 3, 4 and 7, while all its data
sat in domain 0, where its main thread had read the file. Only 1% of its
threads' time was local, and it ran at less than half the speed of a bound
step.
