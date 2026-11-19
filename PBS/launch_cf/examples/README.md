# `launch_cf` Examples

These examples show how to run many independent computations, the steps
of a command file, on Derecho's CPU nodes with `launch_cf`, and how to lay
them out so that they cost as little as possible. They start with simple
hello-world-type programs and end with real analyses of ERA5 data.

[`../README.md`](../README.md) describes `launch_cf` and its options. Refer
to that if you need introductory material.

## Before you start

- Set `PBS_ACCOUNT` to your project code: `export PBS_ACCOUNT=<project>`.
  Every submit script uses it.
- Build the small test program that the first examples use by running
  `make hello_omp.exe` in this directory.
- Some examples use options that are newer than the installed `launch_cf`,
  such as waves, `--sync-waves`, `--nodes` and `--rerun`. Until they
  are installed, those examples' scripts put a development copy first in
  `PATH`.

Each example directory has a `README.md`. It describes the purpose of the
example, what to run, and what to expect. Where an example grew out of a longer study, the
full measurements are in a `DETAILS.md` beside it. You don't need those to
follow the examples.

## Where to start

Read the first four in order. After that, pick what fits your work.

### 1. `launch_cf` basics

| example | what it does | what it shows |
| ------- | ------------ | ------------- |
| [`derecho-640procs`](derecho-640procs) | 640 one-line steps on 5 nodes | how a command file becomes a PBS job array, one node per array index; where output goes; where each step ran |

### 2. Where steps run, and why it matters

| example | what it does | what it shows |
| ------- | ------------ | ------------- |
| [`thread-placement`](thread-placement) | a 16-thread program, 8 steps per node, run three ways | cores, hardware threads and **NUMA domains**; how `numactl` keeps each step's threads in one domain, and OpenMP binding pins each thread to a core |
| [`numa-python`](numa-python) | threaded NumPy on a month of ERA5, 8 steps per node, with and without `numactl` | why placement changes speed: binding each step to a domain made the steps **twice as fast**. The problem doesn't show on a node with one step |
| [`netcdf-postproc`](netcdf-postproc) | NCO reductions of ERA5 files, one file per step, then a gather | the opposite case: single-threaded steps limited by reading files gain nothing from placement. Also a template for real post-processing: a gather after the steps, a memory check before submitting, failures that can't slip through |
| [`numa-python-advanced`](numa-python-advanced) *(optional)* | `numa-python` with more placements: first touch, interleaved memory, per-thread pinning | why the alternatives to binding fall short |

### 3. Many threaded steps per node

These use a Numba calculation that stands in for memory-bound
post-processing.

| example | what it does | what it shows |
| ------- | ------------ | ------------- |
| [`python-regrid`](python-regrid) | 32 steps of 8 threads, bound or not, on 2 nodes or 1 node in waves | **waves**: more steps per node than fit at once; how starting Python can dominate a short step |
| [`python-regrid-nodes-rerun`](python-regrid-nodes-rerun) | the same steps with `--nodes`, on the `preempt` queue, then `--rerun` | choosing the number of nodes; running at **a fifth of the cost** on the preempt queue, and finishing with `--rerun` the steps cut short |
| [`python-regrid-sweep-sync`](python-regrid-sweep-sync) | 1 to 8 threads per step × 1 to 8 waves per node, bound or not | once steps are bound, threads per step and waves hardly change the cost; `--sync-waves` keeps bound steps in their domains |

### 4. Real data and the queue

| example | what it does | what it shows |
| ------- | ------------ | ------------- |
| [`python-regrid-climo`](python-regrid-climo) | builds a 1991–2020 climatology once, then computes the anomaly of each ERA5 day, one file per step | a two-stage workflow; steps that decompress real data; the cheapest layout: 1 thread per step, bound, one node in several waves |
| [`python-regrid-io-arrays`](python-regrid-io-arrays) | the same 1024 files as job arrays of 1 to 64 nodes, submitted together | how array shape affects queue priority, time to finish, and cost |

## What they cost

The first examples cost very little. Some later ones run large studies, and
each README says what its runs cost. The largest are these:

| example | run | about |
| ------- | --- | ----: |
| `numa-python` | the two `launch_cf` runs | 16 core-hours |
| `python-regrid-climo` | building the climatology, once | 107 core-hours |
| `python-regrid-sweep-sync` | the full sweep (each README shows a single small run first) | 430 core-hours |
| `python-regrid-io-arrays` | one set of seven runs | 330 core-hours |

## Shared files

| file | role |
| ---- | ---- |
| [`hello_omp.cpp`](hello_omp.cpp) | prints where each of its OpenMP threads runs; built by `make hello_omp.exe` |
| [`gen_cmdfile.sh`](gen_cmdfile.sh) | writes a command file of N steps of one program |
| [`gen_cmdfile_numactl.sh`](gen_cmdfile_numactl.sh) | the same, with each step bound to a NUMA domain |
| [`parse_steps.py`](parse_steps.py) | summarizes where the steps of a `hello_omp` run landed |
| [`Makefile`](Makefile) | builds `hello_omp.exe` and the command files of the first examples; the comment at its top lists the targets |
