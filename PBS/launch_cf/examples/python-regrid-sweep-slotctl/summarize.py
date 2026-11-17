#!/usr/bin/env python3
"""Summarize the runs submit_runs.sh made, one line per run.

Usage:  ./summarize.py [--nodes] [--csv steps.csv]

Finds each run from logs/launch_cf.<placement>.tTT.nNNN.wW.log (its job id),
reads its steps' output in stdout-<job id>/, and the node times from the
job's PBS output, one file per node (array index).  Times come from the
steps' own clocks unless noted.  Columns:

  run       placement, threads per step, total steps
  nodes     nodes (array indices) the run used
  waves     waves per node: steps per node / steps at once (128 threads)
  ok        steps that reported a result
  comp s    the steps' compute phase: mean (slowest)
  GB/s      each step's estimated memory bandwidth: mean (min - max)
  start s   the rest of a step, mostly starting Python and loading Numba: mean
  node-s    node time: each node's first step start to last step end, summed
  PBS       node time as launch_cf reports it on each node (whole seconds),
            summed: includes the job's own start, e.g. activating conda
  ms/step   node-s / steps: the cost per step to compare across runs
  fill      share of the nodes' cores busy with a step during node-s
  imbal     per node, its time / (its total step time / steps at once):
            1.00 when its waves pack perfectly; mean and worst node
  dom max   bound runs: most steps ever running in one NUMA domain of a
            node at once (should be at most steps at once / 8)
  wall s    first start to last end over all nodes: depends also on when
            PBS started each array index

--nodes also prints a line per node; --csv writes one row per step.
"""
import argparse
import csv
import glob
import math
import os
import re
import statistics as st
import sys
from collections import defaultdict

CORES_PER_NODE = 128
DOMAINS = 8

TAG_RE = re.compile(r"launch_cf\.(unbound|bound)\.t(\d+)\.n(\d+)(?:\.w(\d+))?\.log$")
JOB_RE = re.compile(r"^(\d+)(\[\])?\.(\S+)\s*$", re.M)
REPORT_RE = re.compile(
    r"Threads: *(\d+)\] Alloc: ([\d.]+)s \| Compute: ([\d.]+)s \| "
    r"Est\. BW: *([\d.]+) GB/s")
ELAPSED_RE = re.compile(r"Elapsed time: (?:(\d+):)?(\d+):([\d.]+)")
PLACE_RE = re.compile(r"placement=(\S+) slot=(\S+) domain=(\S+) threads=(\d+)"
                      r"(?: index=(\d+) host=(\S+))? start=([\d.]+) end=([\d.]+)")
DONE_RE = re.compile(r"Done: PBS_ARRAY_INDEX=(\d+) took (\d+) seconds")


def read_steps(stdout_dir, steps_per_node):
    steps = []
    for path in sorted(glob.glob(os.path.join(stdout_dir, "step-*.out"))):
        text = open(path).read()
        r, e, p = REPORT_RE.search(text), ELAPSED_RE.search(text), PLACE_RE.search(text)
        step = int(re.search(r"step-(\d+)", path).group(1))
        # launch_cf gives each array index a block of steps_per_node steps
        index = (step - 1) // steps_per_node
        if not (r and e and p):
            steps.append({"step": step, "index": index, "ok": False})
            continue
        h, m, s = e.groups()
        steps.append({
            "step": step, "ok": True,
            "index": int(p.group(5)) if p.group(5) else index,
            "host": p.group(6) or "?",
            "threads": int(r.group(1)), "alloc": float(r.group(2)),
            "compute": float(r.group(3)), "gbps": float(r.group(4)),
            "elapsed": int(h or 0) * 3600 + int(m) * 60 + float(s),
            "slot": p.group(2), "domain": p.group(3),
            "start": float(p.group(7)), "end": float(p.group(8)),
        })
    return steps


def max_per_domain(steps):
    """Most steps running in one domain at any moment."""
    events = []
    for s in steps:
        if s["domain"] != "-":
            events += [(s["start"], 1, s["domain"]), (s["end"], -1, s["domain"])]
    count, most = {}, 0
    for _, delta, d in sorted(events, key=lambda ev: (ev[0], ev[1])):
        count[d] = count.get(d, 0) + delta
        most = max(most, count[d])
    return most


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--nodes", action="store_true", help="also print a line per node")
    ap.add_argument("--csv", help="also write one row per step to this file")
    args = ap.parse_args()

    runs = []
    for log in glob.glob("logs/launch_cf.*.log"):
        m = TAG_RE.search(log)
        if not m:
            continue
        placement, threads, nsteps = m.group(1), int(m.group(2)), int(m.group(3))
        at_once = CORES_PER_NODE // threads
        waves = int(m.group(4)) if m.group(4) else math.ceil(nsteps / at_once)
        jobs = JOB_RE.findall(open(log).read())
        runs.append((placement, threads, nsteps, waves, jobs[-1] if jobs else None))
    if not runs:
        sys.exit("no logs/launch_cf.*.log found -- run ./submit_runs.sh first")
    runs.sort(key=lambda r: (r[0] != "unbound", r[1], r[2], r[3]))

    print(f"{'run':<18} {'nodes':>5} {'waves':>5} {'ok':>7} {'comp s':>12} "
          f"{'GB/s':>18} {'start s':>7} {'node-s':>7} {'PBS':>5} {'ms/step':>7} "
          f"{'fill':>5} {'imbal':>11} {'dom max':>7} {'wall s':>7}")
    rows = []
    for placement, threads, nsteps, waves, job in runs:
        name = f"{placement} t{threads:02d} n{nsteps:03d}"
        if not job:
            print(f"{name:<18} no job id in its log (dry run?)")
            continue
        jobnum, _, server = job
        stdout_dir = f"stdout-{jobnum}.{server}"
        if not os.path.isdir(stdout_dir):
            print(f"{name:<18} job {jobnum}: no {stdout_dir}/ yet")
            continue
        at_once = min(CORES_PER_NODE // threads, nsteps)
        steps = read_steps(stdout_dir, waves * at_once)
        good = [s for s in steps if s["ok"]]
        pbs = {}
        for out in glob.glob(f"*.o{jobnum}*"):
            for idx, secs in DONE_RE.findall(open(out).read()):
                pbs[int(idx)] = int(secs)
        if not good:
            print(f"{name:<18} {'':>5} {waves:>5} {0:>3}/{nsteps:<3} no step results")
            continue

        by_node = defaultdict(list)
        for s in good:
            by_node[s["index"]].append(s)
        node_s = busy = 0.0
        imbal, dom, per_node = [], 0, []
        for idx in sorted(by_node):
            ns = by_node[idx]
            span = max(s["end"] for s in ns) - min(s["start"] for s in ns)
            b = sum(s["end"] - s["start"] for s in ns)
            node_at_once = min(at_once, len(ns))
            node_s += span
            busy += b
            imbal.append(span / (b / node_at_once))
            if placement == "bound":
                dom = max(dom, max_per_domain(ns))
            per_node.append((idx, ns[0]["host"], len(ns), span, pbs.get(idx),
                             b * threads / (span * CORES_PER_NODE), imbal[-1],
                             max(s["compute"] for s in ns)))

        comp = [s["compute"] for s in good]
        gbps = [s["gbps"] for s in good]
        startup = [s["elapsed"] - s["compute"] - s["alloc"] for s in good]
        fill = busy * threads / (node_s * CORES_PER_NODE)
        wall = max(s["end"] for s in good) - min(s["start"] for s in good)
        pbs_total = f"{sum(pbs.values())}" if len(pbs) == len(by_node) else "?"
        dom_col = f"{dom}/{math.ceil(at_once / DOMAINS)}" if placement == "bound" else "-"

        print(f"{name:<18} {len(by_node):>5} {waves:>5} {len(good):>3}/{nsteps:<3} "
              f"{st.mean(comp):5.2f} ({max(comp):4.2f}) "
              f"{st.mean(gbps):5.1f} ({min(gbps):4.1f}-{max(gbps):5.1f}) "
              f"{st.mean(startup):7.2f} {node_s:7.1f} {pbs_total:>5} "
              f"{1000 * node_s / nsteps:7.0f} {100 * fill:4.0f}% "
              f"{st.mean(imbal):5.2f}/{max(imbal):5.2f} {dom_col:>7} {wall:7.1f}")
        if args.nodes:
            for idx, host, n, span, p, f, im, cmax in per_node:
                print(f"    index {idx:<3} {host:<8} {n:>4} steps  node-s {span:6.1f}"
                      f"  PBS {p if p is not None else '?':>4}  fill {100 * f:3.0f}%"
                      f"  imbal {im:4.2f}  slowest comp {cmax:4.2f}")

        for s in steps:
            rows.append({"placement": placement, "threads": threads,
                         "nsteps": nsteps, "waves": waves, "job": jobnum, **s})

    if args.csv and rows:
        keys = ["placement", "threads", "nsteps", "waves", "job", "step", "ok",
                "index", "host", "slot", "domain", "start", "end", "elapsed",
                "alloc", "compute", "gbps"]
        with open(args.csv, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=keys, extrasaction="ignore")
            w.writeheader()
            w.writerows(rows)
        print(f"\nwrote {len(rows)} steps to {args.csv}")


if __name__ == "__main__":
    main()
