#!/usr/bin/env python3
"""Summarize the runs submit_study.sh made, one line per run.

Usage:  ./summarize_study.py [--nodes]

Finds each run's job id in logs/launch_cf.<run>.log.  When each step started
and finished comes from launch_cf's PBS output, one file per node (to the
second); what each step did comes from its output in stdout-<job id>/.
Columns:

  run          script, placement (b = bound + synchronized waves,
               u = unbound), threads per step
  nodes        nodes (array indices) the run used
  waves        waves per node
  ok           steps that exited 0 and reported a result
  step s       a step's elapsed time (/usr/bin/time), mean (max): includes
               starting Python and loading the cached Numba code
  read s       time blocked on data: Read (io) or Wait (pario), mean
  unsh s       pario's unshuffle, mean
  comp s       the Numba kernels, mean
  RSS GB       a step's peak memory, mean (max)
  node GB      steps at once x max RSS: the most one node's steps can hold
  node-s       each node's first step start to last step end, summed
  node-s/step  node-s / steps: the cost per file, to compare across runs
  fill         share of the nodes' cores inside a running step during node-s
  wall s       first start to last end over all nodes

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

TAG_RE = re.compile(r"launch_cf\.(io|pario|keep|climoh5|climo)\.(bound|unbound)\.t(\d+)\.n(\d+)\.w(\d+)\.f(\d+)\.log$")
# the first single-node study: bound, 1 node, as many waves as 128 files need
OLD_TAG_RE = re.compile(r"launch_cf\.(io|pario)\.t(\d+)\.f(\d+)\.log$")
JOB_RE = re.compile(r"^(\d+)(\[\])?\.(\S+)\s*$", re.M)
EVENT_RE = re.compile(r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) \S+\] "
                      r"(launching|finished ) step (\d+): (?:exit status )?(.*)$", re.M)
INDEX_RE = re.compile(r"PBS_ARRAY_INDEX=(\d+)")
LINE_RE = re.compile(r"^\[(?:h5py|pario|climo|climo-h5py) .*Checksum: [-\d.]+$", re.M)
TIMER_RE = re.compile(r"(Alloc|Climo|Read|Wait|Unshuffle|Compute|Total): ([\d.]+)s")
ELAPSED_RE = re.compile(r"Elapsed time: (?:(\d+):)?(\d+):([\d.]+)")
RSS_RE = re.compile(r"Max RSS: (\d+) KB")


def seconds(stamp):
    return datetime.strptime(stamp, "%Y-%m-%d %H:%M:%S").timestamp()


def read_node(path):
    """One node's steps from launch_cf's PBS output: (index, {step: [start, end, status]})."""
    text = open(path).read()
    m = INDEX_RE.search(text)
    steps = defaultdict(lambda: [None, None, None])
    for stamp, what, step, rest in EVENT_RE.findall(text):
        s = steps[int(step)]
        if what == "launching":
            s[0] = seconds(stamp)
        else:
            s[1], s[2] = seconds(stamp), int(rest)
    return (int(m.group(1)) if m else 0), dict(steps)


def read_step(path):
    try:
        text = open(path).read()
    except OSError:
        return None
    line, e, r = LINE_RE.search(text), ELAPSED_RE.search(text), RSS_RE.search(text)
    if not (line and e and r):
        return None
    timers = {k: float(v) for k, v in TIMER_RE.findall(line.group(0))}
    h, m, s = e.groups()
    timers["elapsed"] = int(h or 0) * 3600 + int(m) * 60 + float(s)
    timers["rss"] = int(r.group(1)) / 1e6       # KB -> GB
    timers["read"] = timers.get("Read", timers.get("Wait", 0.0))
    return timers


def find_runs():
    runs = []
    for log in glob.glob("logs/launch_cf.*.log"):
        m, old = TAG_RE.search(log), OLD_TAG_RE.search(log)
        if m:
            script, placement, t, n, w, f = m.groups()
            run = (script, placement, int(t), int(n), int(w), int(f))
        elif old:
            script, t, f = old.groups()
            t = int(t)
            run = (script, "bound", t, 1, 128 // (CORES_PER_NODE // t), int(f))
        else:
            continue
        jobs = JOB_RE.findall(open(log).read())
        runs.append(run + (jobs[-1] if jobs else None,))
    runs.sort(key=lambda r: ({"climo": 0, "climoh5": 1, "pario": 2, "keep": 3}.get(r[0], 3), r[1], r[2], -r[3], r[5]))
    return runs


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--nodes", action="store_true", help="also print a line per node")
    args = ap.parse_args()

    runs = find_runs()
    if not runs:
        sys.exit("no logs/launch_cf.*.log found -- run ./submit_study.sh first")

    print(f"{'run':<14} {'nodes':>5} {'waves':>5} {'ok':>9} {'step s':>13} {'read s':>6} "
          f"{'unsh s':>6} {'comp s':>6} {'RSS GB':>11} {'node GB':>7} {'node-s':>6} "
          f"{'node-s/step':>11} {'fill':>5} {'wall s':>6}")
    prev = None
    for script, placement, threads, nnodes, waves, first, job in runs:
        name = f"{script} {placement[0]} t{threads:02d}"
        if prev and prev != (script, placement, threads):
            print()
        prev = (script, placement, threads)
        if not job:
            print(f"{name:<14} no job id in its log (dry run?)")
            continue
        jobnum, _, server = job
        outs = [p for p in glob.glob(f"*.o{jobnum}*") if os.path.isfile(p)]
        if not outs:
            print(f"{name:<14} {nnodes:>5} {waves:>5}  job {jobnum}: no PBS output yet")
            continue
        at_once = CORES_PER_NODE // threads
        nsteps = nnodes * waves * at_once

        node_s = busy = 0.0
        res, first_t, last_t, per_node = [], [], [], []
        for idx, steps in sorted(read_node(p) for p in outs):
            ended = {k: v for k, v in steps.items() if None not in v}
            if not ended:
                continue
            start = min(v[0] for v in ended.values())
            end = max(v[1] for v in ended.values())
            span = max(end - start, 1)
            b = sum(v[1] - v[0] for v in ended.values())
            node_s += span
            busy += b
            first_t.append(start)
            last_t.append(end)
            good = [r for k, v in ended.items() if v[2] == 0
                    for r in [read_step(f"stdout-{jobnum}.{server}/step-{k:05d}.out")] if r]
            res += good
            per_node.append((idx, len(ended), span, b * threads / (span * CORES_PER_NODE)))
        if not res:
            print(f"{name:<14} {nnodes:>5} {waves:>5} {0:>4}/{nsteps:<4} no step results")
            continue

        mean = lambda key: st.mean(r.get(key, 0.0) for r in res)
        el = [r["elapsed"] for r in res]
        rss = [r["rss"] for r in res]
        unsh = f"{mean('Unshuffle'):6.2f}" if script not in ("io", "climoh5") else f"{'-':>6}"
        fill = busy * threads / (node_s * CORES_PER_NODE)
        print(f"{name:<14} {len(per_node):>5} {waves:>5} {len(res):>4}/{nsteps:<4} "
              f"{st.mean(el):6.1f} ({max(el):4.0f}) {mean('read'):6.2f} {unsh} "
              f"{mean('Compute'):6.2f} {st.mean(rss):5.2f} ({max(rss):4.2f}) "
              f"{at_once * max(rss):7.0f} {node_s:6.0f} {node_s / nsteps:11.2f} "
              f"{100 * fill:4.0f}% {max(last_t) - min(first_t):6.0f}")
        if args.nodes:
            for idx, n, span, f in per_node:
                print(f"    index {idx:<3} {n:>4} steps  node-s {span:5.0f}  fill {100 * f:3.0f}%")


if __name__ == "__main__":
    main()
