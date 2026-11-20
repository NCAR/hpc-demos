# Surviving Preemption in the `preempt` Queue

Jobs submitted to NCAR's `preempt` queue run on resources that are not currently needed by
higher-priority work in `main` or `develop`, and are charged at a queue factor of **0.2**
instead of 1.0.  The tradeoff is that such a job can be evicted at any time when the
resources are reclaimed.

Eviction is not silent.  PBS sends the job a **`SIGTERM`**, waits **10 minutes**, and only
then sends `SIGKILL`.  An application that catches that signal can write a checkpoint and
exit gracefully inside the grace period, rather than losing everything it has computed
since it started.

This directory is a minimal, runnable demonstration of that handshake, in C, Fortran, bash,
Python, and MPI.  It is the code behind the examples in the
[NCAR job preemption documentation](https://ncar-hpc-docs.readthedocs.io/en/latest/pbs/preemption/).

# The Pattern

Every example here implements the same four steps.  Only the syntax changes.

1. **Register a handler at startup** for `SIGTERM` (and `SIGINT`, `SIGUSR1`) before the
   main loop begins.
2. **Do almost nothing inside the handler.**  Set a `checkpoint_requested` flag and return.
   A signal handler interrupts the program at an arbitrary instruction; performing I/O,
   MPI calls, or cleanup from inside one is not safe.
3. **Poll the flag from the main loop**, at a point where the program state is consistent —
   typically the top or bottom of a timestep — and call the checkpoint routine there.
4. **Restore the default handler** after setting the flag, so that a second signal
   terminates the process normally instead of being swallowed.  (`minimal_mpi.cpp` is the
   one exception, and leaves its handler installed on purpose: it exits at the end of its
   checkpoint, so there is no second signal to worry about.)

The main loops in these demos are `sleep()` loops standing in for real work, so that the
response to a signal is easy to watch in the job output.

# What Is Here

| File | Role |
| ---- | ---- |
| `my_sig_handler.c`, `my_sig_handler.h` | The shared C handler used by the C, Fortran, and `demo_mpi` examples.  Also exports trailing-underscore aliases (`register_sig_handler_`, `checkpoint_requested_`) so Fortran can call it directly. |
| `main.c` | C driver: register, loop, poll, checkpoint. |
| `fmain.f` | F77 driver calling the same C handler through the underscore aliases. |
| `demo.sh` | The same pattern in bash, using `trap`. |
| `demo.py` | The same pattern in Python, using the `signal` module. |
| `main_mpi.cpp` | MPI driver that checkpoints and then *continues* running. |
| `minimal_mpi.cpp` | Self-contained MPI driver that checkpoints and then exits cleanly.  Start here for MPI. |
| `preempt_gust.sh` | Batch script running the four serial demos in a loop. |
| `preempt_gust_mpi.sh` | Batch script running the MPI demo in a loop. |

## The MPI Case

MPI needs one additional step, and it is the part most easily gotten wrong.

A signal is delivered per *process*.  There is no guarantee that every rank receives it, so
if each rank decides independently whether to checkpoint, the ranks that were signaled will
enter the checkpoint routine while the others continue — and the job deadlocks at the next
collective operation.

The decision must therefore be made collectively.  `mpi_checkpoint_requested()` performs an
`MPI_Allreduce` with `MPI_MAX` over the local flag, so that if *any* rank was signaled,
*every* rank agrees to checkpoint:

```c
int mpi_checkpoint_requested (MPI_Comm comm)
{
  int local_checkpoint_req = checkpoint_req;
  MPI_Allreduce(&local_checkpoint_req, &checkpoint_req,
                1, MPI_INT, MPI_MAX, comm);
  return checkpoint_req;
}
```

Because it is a collective, it is blocking, and must be called from a point every rank
reaches on every iteration.

# Building and Running

```
make all                # cdemo, fdemo, demo_mpi, minimal_mpi
make run                # qsub preempt_gust.sh      (serial demos)
make run_mpi            # qsub preempt_gust_mpi.sh  (MPI demo)
make runmany            # submit 10 MPI jobs, to provoke real contention
make qdelall            # qdel this demo's jobs
make clean              # remove binaries and objects
```

## Testing Without Waiting to Be Preempted

Rather than waiting for the scheduler to reclaim your nodes, send the signal by hand from a
login node and watch the job output.  `qsig` delivers the signal to the job's processes
exactly as preemption would:

```
qsig -s SIGTERM <jobid>
```

You should see the handler report the signal, the checkpoint routine run to completion, and
then — for `minimal_mpi` — a clean exit.

# Porting These Scripts to Derecho

The two batch scripts were written for Gust, Derecho's retired test system, and need
updating before they will run:

- `#PBS -A <project_code>` is a placeholder in both scripts; substitute your project code.
- `TMPDIR` points at `/glade/gust/scratch/${USER}/temp`; on Derecho use
  `/glade/derecho/scratch/${USER}/temp`.
- `preempt_gust.sh` requests `mem=250G`, which exceeds what a Derecho compute node offers;
  use `mem=235G` or less.
- `preempt_gust.sh` also requests 8 nodes but only runs single-process demos on the first
  one.  Reduce it to `select=1:ncpus=1` unless you are deliberately holding nodes to
  observe preemption.
- The `qdelall` target in the `Makefile` filters `qstat` output on `gusched`; on Derecho
  that is `desched`.

Neither script sets `#PBS -r`.  Add `#PBS -r y` if you want a preempted job requeued and
run again from the beginning, or `#PBS -r n` if you would rather it stay dead once it has
checkpointed — worth deciding deliberately, since both demo scripts loop forever.

# Further Reading

- [Job preemption with PBS](https://ncar-hpc-docs.readthedocs.io/en/latest/pbs/preemption/)
- [Queues and charging](https://ncar-hpc-docs.readthedocs.io/en/latest/pbs/charging/)

This demo was originally developed at https://github.com/benkirk/demo_preempt.
