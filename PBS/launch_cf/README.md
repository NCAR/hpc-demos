# Using Job Arrays to Launch a Command File

Multiple Program, Multiple Data (MPMD) jobs run multiple independent, typically serial executables simultaneously. Such jobs can easily be dispatched with PBS job arrays, even on machines like Derecho where compute nodes are exclusively and entirely assigned to a users' job.
Here we discuss a BASH script that is designed to conveniently run MPMD
workflows, `launch_cf`. Below you will find an introduction to the command.

An extensive set of examples demonstrating `launch_cf` and how to use
it to gain productivity and efficiency in your workflows, from a first job to real analyses of ERA5 data, are in [`examples/`](examples/README.md), with a suggested reading order. These examples include a demonstration of binding processes and threads to NUMA regions and a demonstration of
running steps in multiple waves on a single node, both of which can
provide efficiency improvements.

# Where `launch_cf` Comes From

`launch_cf` is maintained in the [NCAR/pbstools](https://github.com/NCAR/pbstools) repository,
alongside `qcmd` and `qinteractive`, and CSG installs it on both Derecho and Casper so that it
is already on your default `PATH`.  Nothing needs to be built or cloned to use it:

```
$ which launch_cf
```

This directory carries **no copy of its own**, deliberately — every example below invokes
whichever `launch_cf` your environment provides, so the tutorial cannot drift from the supported
version.  Changes to the tool itself, and the tests that cover them, belong in
[NCAR/pbstools](https://github.com/NCAR/pbstools) (`bin/launch_cf`, `share/launch_cf.pbs`, and
`tests/`), not here.


# How `launch_cf` Runs a Command File

`launch_cf` reads a command file, one command per line. Each line is a
**step**: a program run on its own, independent of the others. `launch_cf`
submits a PBS **job array**, one sub-job per node, and gives each node a
block of consecutive steps:

- **Steps at once.** A node runs up to `#CPUS / #Threads/step` steps at the
  same time: for example, 128 single-threaded steps on a Derecho node, or
  32 steps of 4 threads.
- **Steps per node.** By default each node gets as many steps as it runs at
  once, so every step starts right away and the job array has as many nodes
  as that takes. 640 single-threaded steps run on 5 nodes, for example.
- **Waves.** A node can also be given more steps than it runs at once. It
  then starts the next step each time a running one finishes, so its steps
  run in waves. See [Waves](#waves).

Because each node is its own sub-job, PBS can start the nodes of a large job
at different times, as nodes come free, and a node that fails or is taken
back doesn't affect the others.

# Command File

Consider a command file as follows.

`cmdfile`:
```
# comments can be included and will be skipped during execution
./cmd1.exe < input1 # comments are allowed for steps too, but not required
./cmd2.exe < input2
./cmd3.exe < input3
./cmd4.exe --flag1 0.1 --long-flag-name "special-input-case" \
   -flag-after "line continuation"
...
./cmdN.exe < inputN
```

Blank lines and lines starting with `#` are not steps. Each step runs in a
bash shell, from the directory you submitted from, so all commands should be
either in your `PATH` or given relative to that directory. A step can be any
shell command line: it can set environment variables, or start with a
command such as `numactl` that runs the rest of the line.

Then,

`launch_cf <PBS Submission Args> [command file]`

The command file defaults to `./cmdfile`. For example,

`launch_cf -A <account> -l walltime=1:00:00`

## Examples

Launch the commands listed in `./cmdfile`, one per CPU:
```
launch_cf -A PBS_ACCOUNT -l walltime=1:00:00
```

Launch the OpenMP-threaded commands listed in `./omp_cmdfile`, 32 steps of 4
threads per node:
```
launch_cf -A PBS_ACCOUNT -l walltime=1:00:00 --nthreads 4 --steps-per-node 32 ./omp_cmdfile
```

Spread the commands in `./cmdfile` over 4 nodes, however many there are:
```
launch_cf -A PBS_ACCOUNT -l walltime=4:00:00 --nodes 4 ./cmdfile
```

Give each node 3 waves of 32 four-thread steps, 96 steps per node:
```
launch_cf -A PBS_ACCOUNT -l walltime=3:00:00 --nthreads 4 --waves 3 ./omp_cmdfile
```

Resubmit the steps of job 1234567 that did not succeed:
```
launch_cf -A PBS_ACCOUNT -l walltime=1:00:00 --rerun 1234567
```

`launch_cf` assumes reasonable defaults on Derecho and Casper for the number
of steps to run per node, memory per node, PBS queues, etc. Each of these can
be set with the options described in [Optional Parameters](#optional-parameters).

# Output

`launch_cf` writes, in the directory you submitted from:

- `stdout-<job id>/step-NNNNN.out`: the standard output and standard error of
  step *NNNNN*, numbered from 1 in command-file order;
- `<job name>.o<job id>.<index>` (`launch_cf.o...` by default; no `.<index>`
  for a one-node job): one log per node, recording when each step was launched, when it finished and its
  exit status, and how long the node took.

```
[2026-11-13 15:26:18 MST] launching step 00001: OMP_NUM_THREADS=8 numactl --cpunodebind=0 --membind=0 ./run_step.sh 1 40
...
[2026-11-13 15:26:24 MST] finished  step 00006: exit status 0
...
Done: PBS_ARRAY_INDEX=0 took 7 seconds, finished on Fri Nov 13 03:26:24 PM MST 2026
```

**Check the steps, not just the node logs.** A node reports `Done` once its
steps have ended, whether or not they succeeded; the exit status of each step
is in its `finished` line. `--rerun` uses these lines to find the steps that
did not succeed.

A step can use the shell variable `${step}`, its line number counting from
0, for example to name its own output files.

# Waves

Each node runs up to `#CPUS / #Threads/step` steps at once. Give a node more
steps than that, and it runs them in waves: when a running step finishes,
the node starts the next. Three options set how many steps each node gets;
give at most one of them:

| option | each node gets |
| ------ | -------------- |
| `--steps-per-node N` | *N* steps |
| `--nodes N` | the steps divided over *N* nodes, rounded up |
| `--waves N` | *N* times as many steps as it runs at once |

For example, 512 single-threaded steps run on 4 nodes with no options (128
steps per node, all at once), or on 1 node in 4 waves with `--nodes 1` or
`--waves 4`.

Why use waves:

- **Fewer nodes, the same node time.** One node running 4 waves uses about as
  much node time as 4 nodes running 1, and a small job often starts sooner.
  In the [examples](examples/README.md), fewer nodes in more waves usually
  cost *less*, because fewer programs start at the same moment.
- **Steps of uneven length pack better.** A short step's place is filled as
  soon as it ends, instead of the node waiting for its slowest step.
- **Fewer array sub-jobs.** A very large command file needs fewer nodes, so
  a smaller job array.

What to watch:

- **Walltime.** A node is busy for about as long as its waves in a row.
  `launch_cf` reports how many waves each node will run, but cannot know how
  long the steps take; ask for enough walltime for all of them.
- **Steps bound to cores or NUMA domains.** By default a new step starts in
  place of whichever step finished first. If each line of the command file
  binds its step to particular cores, for example with
  `numactl --cpunodebind=d`, where `d` is a NUMA domain that can be seen from
  `numactl -H` or `lscpu` output. The new step may land where steps are still
  running while other cores sit idle. `--sync-waves` prevents this: each wave
  starts only once every step of the wave before it has finished, so the
  steps running together are always one wave's lines. Each wave then lasts
  as long as its slowest step, which costs little when steps take about the
  same time.

`--ppn` interacts with waves: without it, `launch_cf` asks for enough CPUs to
run all of a node's steps at once, up to a full node; with it, `launch_cf`
asks for that many CPUs, and the steps that don't fit run in waves. This is
helpful when steps require more memory for the combined number of steps than
can be accommodated by the node.

The examples [`python-regrid`](examples/python-regrid) and
[`python-regrid-sweep-sync`](examples/python-regrid-sweep-sync) show waves
and `--sync-waves` at work, and what they cost.

# Rerunning Steps That Did Not Succeed

`--rerun JOBID` submits again only the steps of an earlier `launch_cf` job
that did not succeed:

- steps that exited with an error;
- steps that were cut short, because their node was preempted, deleted with
  `qdel`, or ran out of walltime;
- steps that never started.

```
launch_cf -A PBS_ACCOUNT -l walltime=1:00:00 --rerun 1234567
```

`launch_cf` lists the steps it found and why, writes them to a new command
file, `./<command file>.1234567.rerun`, and submits that. If every step
succeeded, it says so and submits nothing. Repeat with each new job id until
nothing is left.

- **Run it from the directory the job was submitted from.** It reads the
  job's node logs and step output there. Don't delete them, or edit the
  command file, until everything has run. If the job's logs don't record its
  command file, give the command file as well.
- **Choose the layout again.** The options of the earlier job are not reused:
  give `-A`, `-l walltime`, the queue, `--nthreads` and so on for what is
  left, which is often far fewer steps.
- **Rerun steps keep their numbers.** Each line of the rerun command file
  starts with `step=N;`, so `${step}` and the name of its output,
  `step-NNNNN.out` in the new job's `stdout-` directory, are those of the
  original step.
- **Make steps safe to run twice.** A step cut short may have written part of
  its output. When it reruns, it should start over or carry on from where it
  stopped, not trip over what it left behind.

PBS doesn't put a job back in the queue reliably: a job array can't be made
non-rerunnable, and on Derecho a preempted job is deleted rather than requeued.
`--rerun` is the way to finish the steps such a job didn't.

## The preempt queue

Together, waves of independent steps and `--rerun` make Derecho's `preempt`
queue practical. It runs jobs only on nodes that would otherwise be idle, at
**a fifth of the usual charge**, but can take a node back at any time. With
`launch_cf`, a node taken back loses only the steps it was running or hadn't
started; every other node, and every finished step, is unaffected, and
`--rerun` resubmits the rest. The price is not knowing when the work will
finish. See [`python-regrid-nodes-rerun`](examples/python-regrid-nodes-rerun)
for a worked example, including a real preemption.

# The Generated PBS Script

`launch_cf` does not submit a job directly from its own command line.  Instead it writes a complete, self-contained PBS job script into your submission directory and submits *that*.  Everything the job requests appears as an ordinary `#PBS` directive, along with a header recording how, when, and from where the script was generated:

```
#!/bin/bash
#PBS -N launch_cf
#PBS -j oe
#PBS -q main
#PBS -l select=1:ncpus=128:mpiprocs=18:ompthreads=7:mem=235GB
#PBS -J 0-66
#PBS -A <account>
#PBS -l walltime=1:00:00
#PBS -l job_priority=economy

#----------------------------------------------------------------------------
# PBS job script generated by launch_cf.
#
#   generated       : Mon Sep 14 10:47:36 MDT 2026
#   submission dir  : /glade/derecho/scratch/<user>/run
#   launch_cf call  : launch_cf -A <account> -l walltime=1:00:00 ... ./cmdfile
#
#   command file    : /glade/derecho/scratch/<user>/run/cmdfile
#   total steps     : 1200
#   steps / node    : 18
#   threads / step  : 7
#   cpus / node     : 128
#   array indices   : 0-66 (67 array steps)
...
```

This makes the job much easier to understand after the fact than reconstructing it from `qstat -f`, and the script can be read, edited, and resubmitted by hand with plain `qsub` without re-running `launch_cf`.

By default the script is named `./launch_cf.<command file>.<YYYYmmdd-HHMMSS>.pbs`; use `--script` to choose your own name.

## Dry runs

`--dryrun` (or `--dry-run`) reports what would be requested and writes the PBS script, but does not submit anything:

```
launch_cf -A PBS_ACCOUNT -l walltime=1:00:00 --script ./my_job.pbs --dryrun ./cmdfile
```

This is the easiest way to check the resulting select statement, array range, waves per node, and pass-through PBS options before committing to a large job.  When you are satisfied, submit the generated script directly:

```
qsub ./my_job.pbs
```

# Environment Configuration

The steps in the command file are launched from a bash shell in the user's default environment. The optional file `config_env.sh` is "sourced" from the run directory on each node before any step runs, in case environment modification is required, for example to load a particular module environment, to activate a conda environment, or to set file paths.


# Structure for a launch_cf workflow

The command file, executables, and input files should all reside in the directory from which the job is submitted. If they don't, you need to specify adequate relative or full paths in both your command file and job scripts. The sub-jobs will produce output files that reside in the directory in which the job was submitted. The command file can then be executed with the launch_cf command.  An example structure would look like:

```
> Run_Directory/
   - cmdfile
   - config_env.sh (optional)
   - application.exe
   - data.nc
```


# Optional Parameters

The output of the `launch_cf` help:
```
launch_cf -h
     <-q|--queue PBS_QUEUE>
     <--ppn|--processors-per-node #CPUS>
     <--steps-per-node #Steps/node | --nodes #Nodes | --waves #Waves>
     <--nthreads|--threads-per-step #Threads/step>
     <--sync-waves>
     <--mem|--memory RAM/node>
     <--cpu_type TYPE>
     <--random_start_delay MAX_DELAY (sec)>
     <--script PBS_SCRIPT_NAME>
     <--rerun JOBID>
     <--dryrun|--dry-run>
     -A PBS_ACCOUNT -l walltime=01:00:00
     ... other PBS args ...
     <command file>
```

Where arguments within brackets `< >` are optional, and any argument
`launch_cf` doesn't recognize is passed to `qsub`. The PBS options `-A` and
`-l walltime` are required. The default values of optional parameters assign:
- A single CPU per step
- As many steps per node as the node has CPUs, all running at once, for Derecho. For Casper the default is one step per node.
- A job array of as many nodes (indices) as that takes

## Queue

`-q` or `--queue`: Direct translation from Casper or Derecho queues.  Queue types:

	Derecho:
		- main
		- develop
		- preempt

	Casper:
		- casper

	Cross-submission:
		- casper@casper-pbs
		- main@desched1
		- develop@desched1


## Processors per node

`--ppn` or `--processors`

Equivalent to submitting a PBS resource select statement using `ncpus=X`.

This can be thought of as the number of CPUs available per node that can be used to distribute lines from the command file.

| System  | Default | Max | Min |
| ------- | ------- | --- | --- |
| Derecho | 128     | 128 | 1   |
| Casper  | 1       | 62* | 1   |

**The most available and prioritized Casper HTC Nodes have 62 available processors.    Since Casper has many node types with different CPU amounts, be careful with allocating too many CPUs which will result in jobs never starting.*

This value works with `--steps-per-node` and `--nthreads` to determine the total node and CPU requirements for your job array. See [Waves](#waves) for how it decides which steps run at once.


## Threads per step

`--nthreads` or `--threads-per-step`

The number of threads per line in your command file.  Since each line of the command file is an executable, this is equivalent to assigning the number of threads or CPUs per executable.  It also sets `OMP_NUM_THREADS` for each step, unless the line sets it itself.

| System  | Default | Max    | Min |
| ------- | ------- | ------ | --- |
| Derecho | 1       | ${ppn} | 1   |
| Casper  | 1       | ${ppn} | 1   |


## Steps per node, nodes, waves

`--steps-per-node N`, `--nodes N` or `--waves N`; give at most one.

- `--steps-per-node` assigns the number of lines in your command file that each node runs.  It defaults to the **processors per node (ppn)** divided by the **threads per step (nthreads)**, so that all of a node's steps run at once.  A larger value runs the node's steps in waves.
- `--nodes` spreads the steps over that many nodes, rounding up the steps per node; the last node may get fewer.  If that leaves nodes with nothing to do, `launch_cf` says so and asks for fewer.
- `--waves` gives each node that many waves: `N × (ppn / nthreads)` steps.  The command file must have enough steps to fill them.

Every node is charged in full whether or not its cores are busy, so choose values that fill the nodes.  See [Waves](#waves).

## Synchronized waves

`--sync-waves`

Start each wave of a node's steps only once every step of the wave before it has finished, instead of starting each step as soon as one finishes.  Use it when the lines of the command file bind steps to particular cores or NUMA domains.  See [Waves](#waves).

## Rerun

`--rerun JOBID`

Submit the steps of an earlier `launch_cf` job that did not succeed.  See [Rerunning Steps That Did Not Succeed](#rerunning-steps-that-did-not-succeed).

## Memory

`--mem`

Assigns the amount of memory available per node.  All the steps running at once on a node share it.

| System  | Default (GB) | Max (GB) | Min (GB) |
| ------- | ------------ | -------- | -------- |
| Derecho | 235          | 235      | 4        |
| Casper  | 10           | 733*     | 4        |


**The HTC nodes have a maximum of 733GB of memory per node.  Large memory nodes are available on Casper if needed.*

## CPU Type

Used on Casper to request specific resources.  Check the [Casper Node Types](https://ncar-hpc-docs.readthedocs.io/en/latest/compute-systems/casper/starting-casper-jobs/casper-node-types/) page for available resources and how to request them.

## Random start delay

`--random_start_delay MAX_DELAY`

Wait a random time, up to *MAX_DELAY* seconds, before launching each step, so that many steps don't start at the same moment.

## Generated script name

`--script` or `--script-name`

The path of the PBS job script to generate and submit.  Defaults to `./launch_cf.<command file>.<YYYYmmdd-HHMMSS>.pbs`.  See [The Generated PBS Script](#the-generated-pbs-script).

## Dry run

`--dryrun` or `--dry-run`

Generate the PBS job script and report what would be requested, without submitting anything to the queue.


# Querying a Job Array

To view the progress and details of each index in the job array while running, add the `-t` flag to `qstat` and include the `[]` brackets to indicate that the job is a job array:

```
qstat -t <jobid>[]
```

A job just submitted may take a moment to appear in `qstat`.
