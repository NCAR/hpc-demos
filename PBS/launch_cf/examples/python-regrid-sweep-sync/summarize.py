#!/usr/bin/env python3
"""Summarize the runs submit_runs.sh made, one line per run.

Usage:  ./summarize.py [--nodes]

Finds each run's job id in logs/launch_cf.<placement>.tTT.nNNN.wW.log.  When
each step started and finished comes from launch_cf's own PBS output, one
file per node (to the second); what each step computed comes from its
output in stdout-<job id>/.  Columns:

  run          placement, threads per step, total steps
  nodes        nodes (array indices) the run used
  waves        waves per node; "sync" when launch_cf --sync-waves ran them
  ok           steps that finished with exit status 0 and reported a result
  comp s       the steps' compute phase: mean (slowest)
  GB/s         each step's estimated memory bandwidth: mean (min - max)
  start s      the rest of a step, mostly starting Python and loading Numba: mean
  node-s       each node's first step start to last step end, summed over nodes
  PBS          node time as launch_cf reports it, summed: also counts the
               job's own start, e.g. activating conda
  node-s/step  node-s / steps: the cost per step to compare across runs
  fill         share of the nodes' cores busy with a step during node-s
  imbal        per node, its time / (its total step time / steps at once):
               1.00 when its steps pack perfectly; mean and worst node
  wall s       first start to last end over all nodes: depends also on when
               PBS started each array index

--nodes also prints a line per node.
"""
import argparse
import glob
import os
import re
import statistics as st
import sys
from collections import defaultdict
from datetime import datetime

CORES_PER_NODE = 128

TAG_RE = re.compile(r"launch_cf\.(unbound|bound)\.t(\d+)\.n(\d+)\.w(\d+)\.log$")
JOB_RE = re.compile(r"^(\d+)(\[\])?\.(\S+)\s*$", re.M)
# launch_cf's PBS output
EVENT_RE = re.compile(r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) \S+\] "
                      r"(launching|finished ) step (\d+): (?:exit status )?(.*)$", re.M)
INDEX_RE = re.compile(r"PBS_ARRAY_INDEX=(\d+)")
DONE_RE = re.compile(r"Done: PBS_ARRAY_INDEX=(\d+) took (\d+) seconds")
SYNC_RE = re.compile(r"^waves: synchronized", re.M)
# a step's own output
REPORT_RE = re.compile(r"Host: (\S+) \| Threads: *(\d+)\] Alloc: ([\d.]+)s \| "
                       r"Compute: ([\d.]+)s \| Est\. BW: *([\d.]+) GB/s")
ELAPSED_RE = re.compile(r"Elapsed time: (?:(\d+):)?(\d+):([\d.]+)")


def seconds(stamp):
    return datetime.strptime(stamp, "%Y-%m-%d %H:%M:%S").timestamp()


def read_node(path):
    """One node's steps from launch_cf's PBS output: {step: [start, end, status]}."""
    text = open(path).read()
    m = INDEX_RE.search(text)
    steps = defaultdict(lambda: [None, None, None])
    for stamp, what, step, rest in EVENT_RE.findall(text):
        s = steps[int(step)]
        if what == "launching":
            s[0] = seconds(stamp)
        else:
            s[1], s[2] = seconds(stamp), int(rest)
    done = DONE_RE.search(text)
    return (int(m.group(1)) if m else 0, dict(steps),
            int(done.group(2)) if done else None, bool(SYNC_RE.search(text)))


def read_step(stdout_dir, step):
    try:
        text = open(os.path.join(stdout_dir, f"step-{step:05d}.out")).read()
    except OSError:
        return None
    r, e = REPORT_RE.search(text), ELAPSED_RE.search(text)
    if not (r and e):
        return None
    h, m, s = e.groups()
    elapsed = int(h or 0) * 3600 + int(m) * 60 + float(s)
    alloc, compute = float(r.group(3)), float(r.group(4))
    return {"host": r.group(1), "compute": compute, "gbps": float(r.group(5)),
            "startup": elapsed - compute - alloc}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--nodes", action="store_true", help="also print a line per node")
    args = ap.parse_args()

    runs = []
    for log in glob.glob("logs/launch_cf.*.log"):
        m = TAG_RE.search(log)
        if not m:
            continue
        jobs = JOB_RE.findall(open(log).read())
        runs.append((m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4)),
                     jobs[-1] if jobs else None))
    if not runs:
        sys.exit("no logs/launch_cf.*.log found -- run ./submit_runs.sh first")
    runs.sort(key=lambda r: (r[0] != "unbound", r[1], r[2], r[3]))

    print(f"{'run':<18} {'nodes':>5} {'waves':>6} {'ok':>9} {'comp s':>13} "
          f"{'GB/s':>18} {'start s':>7} {'node-s':>7} {'PBS':>5} {'node-s/step':>11} "
          f"{'fill':>5} {'imbal':>11} {'wall s':>7}")
    for placement, threads, nsteps, waves, job in runs:
        name = f"{placement} t{threads:02d} n{nsteps:03d}"
        if not job:
            print(f"{name:<18} no job id in its log (dry run?)")
            continue
        jobnum, _, server = job
        stdout_dir = f"stdout-{jobnum}.{server}"
        nodes = [read_node(p) for p in glob.glob(f"*.o{jobnum}*") if os.path.isfile(p)]
        if not nodes:
            print(f"{name:<18} job {jobnum}: no PBS output yet")
            continue
        at_once = min(CORES_PER_NODE // threads, nsteps)
        synced = any(n[3] for n in nodes)

        node_s = busy = 0.0
        pbs, imbal, per_node, results = [], [], [], []
        first, last = [], []
        for idx, steps, done, _ in sorted(nodes):
            ended = {k: v for k, v in steps.items() if v[0] is not None and v[1] is not None}
            if not ended:
                continue
            start = min(v[0] for v in ended.values())
            end = max(v[1] for v in ended.values())
            b = sum(v[1] - v[0] for v in ended.values())
            span = max(end - start, 1)
            node_s += span
            busy += b
            first.append(start)
            last.append(end)
            imbal.append(span / (b / min(at_once, len(ended))))
            if done is not None:
                pbs.append(done)
            good = []
            for k, v in ended.items():
                if v[2] == 0:
                    r = read_step(stdout_dir, k)
                    if r:
                        good.append(r)
            results += good
            per_node.append((idx, good[0]["host"] if good else "?", len(ended), span,
                             done, b * threads / (span * CORES_PER_NODE), imbal[-1],
                             max((r["compute"] for r in good), default=0)))
        if not results:
            print(f"{name:<18} {len(nodes):>5} {waves:>6} {0:>4}/{nsteps:<4} no step results")
            continue

        comp = [r["compute"] for r in results]
        gbps = [r["gbps"] for r in results]
        fill = busy * threads / (node_s * CORES_PER_NODE)
        pbs_total = f"{sum(pbs)}" if len(pbs) == len(per_node) else "?"
        wave_col = f"{waves} sync" if synced else f"{waves}"

        print(f"{name:<18} {len(per_node):>5} {wave_col:>6} {len(results):>4}/{nsteps:<4} "
              f"{st.mean(comp):6.2f} ({max(comp):5.1f}) "
              f"{st.mean(gbps):5.1f} ({min(gbps):4.1f}-{max(gbps):5.1f}) "
              f"{st.mean(r['startup'] for r in results):7.2f} {node_s:7.0f} {pbs_total:>5} "
              f"{node_s / nsteps:11.2f} {100 * fill:4.0f}% "
              f"{st.mean(imbal):5.2f}/{max(imbal):5.2f} {max(last) - min(first):7.0f}")
        if args.nodes:
            for idx, host, n, span, p, f, im, cmax in per_node:
                print(f"    index {idx:<3} {host:<8} {n:>4} steps  node-s {span:5.0f}"
                      f"  PBS {p if p is not None else '?':>4}  fill {100 * f:3.0f}%"
                      f"  imbal {im:4.2f}  slowest comp {cmax:5.1f}")


if __name__ == "__main__":
    main()
