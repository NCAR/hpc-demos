# Nodes and the Preempt Queue: Runs

The preempt-queue runs behind [README.md](README.md).

## A job that ran untouched (13 November 2026)

On 13 November 2026, job 8179906 waited in the queue for an hour and a half
(submitted at 15:30, its nodes started between 17:02 and 17:06), while about
1,200 jobs were waiting for `main`. Each of its 4 nodes then ran its 64 steps
in 21.6 to 21.7 minutes, and each step computed for 307 to 328 seconds. No
node was taken back, so all 256 steps succeeded:

```
$ ./rerun_preempt.sh 8179906
All 256 steps of job 8179906 succeeded; there is nothing to rerun.
```

The 1.44 node-hours were charged about 37 core-hours, where `main` would
have charged 185.

## A job that lost a node (17 November 2026)

Whether a job loses nodes depends on how busy Derecho is while it runs. On
17 November 2026, a smaller test did. Job 8219627 ran the 32
steps of `cmdfile.medium` on 2 preempt nodes. PBS took back node 0 after 82
seconds, before any step had finished. Its exit status, 271, is 256 + 15,
which means it was ended by `SIGTERM`. Node 1 started two minutes later, and was ended with
`qdel` a minute into its steps (see [Try `--rerun` without waiting for a preemption](README.md#try---rerun-without-waiting-for-a-preemption)). `--rerun` found all
32 steps cut short:

```
$ ./rerun_preempt.sh 8219627
Job 8219627: 32 of 32 steps did not succeed:
  step 1 of job 8219627: cut short: subjob 0 stopped while it ran
  step 2 of job 8219627: cut short: subjob 0 stopped while it ran
  ...
  ... and 22 more
Wrote ./cmdfile.medium.8219627.rerun, to submit as the command file.
```

and submitted them as job 8219691, again on the preempt queue. It waited two
and a half hours, then ran on 2 nodes, and every step succeeded:

```
$ ./rerun_preempt.sh 8219691
All 32 steps of job 8219691 succeeded; there is nothing to rerun.
```

## Running `--rerun` from the wrong directory

Run from any other directory, `rerun_preempt.sh` stops and says where the job
was submitted from, while PBS still has the job's history (on 17 November it
no longer had the jobs of 13 November):

```
$ cd /some/other/dir
$ .../python-regrid-nodes-rerun/rerun_preempt.sh 8219627
ERROR: no PBS output files of job 8219627 (*.o8219627*) in /some/other/dir
       Job 8219627 was submitted from .../python-regrid-nodes-rerun:
       run launch_cf --rerun from there, e.g. after "cd .../python-regrid-nodes-rerun".
```
