# A First `launch_cf` Job: 640 Steps on 5 Nodes

This is the simplest example: a command file of 640 single-threaded steps,
run on Derecho CPU nodes. It shows

- how a **command file** becomes a **PBS job array**, one node per array
  index;
- where each step's output goes;
- how to see where each step ran.

Each step runs [`../hello_omp.exe`](../hello_omp.cpp) with its step number.
The program does no work: it prints one line saying where it ran and exits.

## A few terms

- **Step:** one line of the command file, run as its own program.
- **Node:** one computer in the cluster. A Derecho CPU node has **128 cores**.
- **Job array:** one PBS job made of numbered sub-jobs that PBS schedules
  separately. `launch_cf` makes each sub-job one node, and gives it a block of
  steps. The number of a sub-job is its **array index**, `PBS_ARRAY_INDEX`.

## The command file

[`cmdfile`](cmdfile) has 640 lines like

```
../hello_omp.exe 1
../hello_omp.exe 2
...
../hello_omp.exe 640
```

`launch_cf` runs one step per core by default, so 128 steps per node, and
640 steps need **5 nodes**: a job array with indices 0 to 4. Index 0 runs steps
1–128, index 1 steps 129–256, and so on.

The command file was written by [`../gen_cmdfile.sh`](../gen_cmdfile.sh); to
write it again, run `make cmdfiles` in the `examples` directory.

## Running it

First build the program, from the `examples` directory:

```
cd PBS/launch_cf/examples
make hello_omp.exe
```

Then, with `$PBS_ACCOUNT` set to your project code:

```
cd derecho-640procs
./submit_launch_cf.sh
```

[`submit_launch_cf.sh`](submit_launch_cf.sh) is one line:

```
launch_cf -A $PBS_ACCOUNT -l walltime=00:10:00 ./cmdfile
```

It prints what it submits and the job's id. Each node runs its steps in a
second or two once it starts, so the job costs very little.

To see what `launch_cf` would submit, without submitting anything, add
`--dryrun`, or run `make dryrun` in the `examples` directory.

## What to expect

`launch_cf` writes:

- `stdout-<job id>/step-NNNNN.out`: what step *NNNNN* printed;
- `launch_cf.o<job id>.<index>`: what each node launched, and when each step
  started and finished.

Each step prints one line:

```
step 210 | host dec1844 | core 115 | thread 0 of 1 | PBS_ARRAY_INDEX=1
```

That is: step 210 ran on node `dec1844`, on CPU 115, as array index 1. Look at
a few:

```
$ cat stdout-*/step-*10.out
step 10 | host dec0993 | core 86 | thread 0 of 1 | PBS_ARRAY_INDEX=0
step 110 | host dec0993 | core 23 | thread 0 of 1 | PBS_ARRAY_INDEX=0
step 210 | host dec1844 | core 115 | thread 0 of 1 | PBS_ARRAY_INDEX=1
step 310 | host dec1844 | core 103 | thread 0 of 1 | PBS_ARRAY_INDEX=2
step 410 | host dec0993 | core 80 | thread 0 of 1 | PBS_ARRAY_INDEX=3
step 510 | host dec0993 | core 113 | thread 0 of 1 | PBS_ARRAY_INDEX=3
step 610 | host dec1844 | core 223 | thread 0 of 1 | PBS_ARRAY_INDEX=4
```

The array index changes every 128 steps. Your hosts and cores will differ.

In this run PBS used only two nodes for the five indices: `dec0993` ran
indices 0 and 3, and `dec1844` ran 1, 2 and 4, one after another. Each index
gets a whole node, but PBS can reuse a node for a later index once the
earlier one has finished. Linux chose the core each step ran on.

## Where did the steps run?

[`../parse_steps.py`](../parse_steps.py) summarizes a whole run. Give it the
`lscpu.txt` here, the output of `lscpu` on a Derecho node, so that it can map
CPU numbers to physical cores:

```
$ python3 ../parse_steps.py stdout-<job id> --lscpu lscpu.txt -o steps.csv
Wrote 640 rows to steps.csv

Physical core usage per array index (128 cores/node):

  index  host        steps   used  reused  unused
  -----  ----------  -----  -----  ------  ------
      0  dec0993       128     53      26      75
      1  dec1844       128     55      24      73
      2  dec1844       128     51      23      77
      3  dec0993       128     56      24      72
      4  dec1844       128     40      19      88
```

`used` is how many physical cores the index's steps reported, `reused` how
many of those took more than one step, and `unused` how many reported none.

Only about 50 of each node's 128 cores were used. Each step finishes in a
fraction of a second, so by the time `launch_cf` starts the last steps, the
first have finished, and Linux reuses their cores. Steps that run longer
spread over the whole node. Where *threaded* steps run is the subject of the
next example, [`../thread-placement`](../thread-placement).

## Troubleshooting

**Check a step's output, not just the job log.** `launch_cf.o*` reports each
node as done even if every step failed. If you forgot to build
`hello_omp.exe`, every `step-*.out` says it couldn't be found.

**Paths are relative to the directory you submitted from.** That is why the
command file says `../hello_omp.exe`.
