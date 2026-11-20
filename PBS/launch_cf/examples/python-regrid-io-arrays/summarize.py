#!/usr/bin/env python3
"""Summarize a set submitted by submit_set.sh and watched by sample_prio.sh.

Usage:  ./summarize.py <set> [--series]

One line per run (one launch_cf job of N nodes x W waves), from runs.csv,
samples/<set>/qstat-final.*.json, samples/<set>/prio.*.txt and launch_cf's
PBS output:

  nodes, waves   the run's shape: array size and waves per node
  wall           walltime requested
  prio           pbs-prio's computed priority of the queued job (the array
                 parent): when first seen, and the highest seen while any of
                 its subjobs were queued
  age s          its eligible_time when last seen queued
  place          its place in line among queued cpu jobs, in the order the
                 scheduler considers them: first seen, and best seen
  wait s         submit to each node's start: first, median, last node
  done s         submit to the last node's end: when the workflow finished
  node-s         each node's start to end, summed: what was charged
  run s          first node's start to last node's end
  steps ok       steps that exited 0, of the steps that ran

--series also prints, for each sample of the pbs-prio cache, every run's
queued / running / finished nodes, priority and place in line.
"""
import csv
import glob
import json
import os
import re
import statistics as st
import sys
from datetime import datetime

PBS_TIME = "%a %b %d %H:%M:%S %Y"


def pbs_epoch(s):
    return datetime.strptime(s, PBS_TIME).timestamp() if s else None


def jobnum(jobid):
    return re.match(r"(\d+)", jobid).group(1)


def read_runs(set_name):
    with open("runs.csv") as f:
        return [r for r in csv.DictReader(f) if r["set"] == set_name]


def read_final(set_name, run):
    """{index: (stime, end)} for each node (subjob) of the run."""
    path = "samples/%s/qstat-final.%s.json" % (set_name, jobnum(run["jobid"]))
    if not os.path.exists(path):
        return None
    # qstat -x of a job array prints "qstat: Unknown Job Id NNN" into its
    # JSON, though it then lists the array; drop that.
    text = re.sub(r"qstat: Unknown Job Id \S+\n?", "", open(path).read())
    jobs = json.loads(text).get("Jobs", {})
    nodes = {}
    for jid, j in jobs.items():
        if j.get("array") == "True":        # the parent of a job array
            continue
        m = re.search(r"\[(\d+)\]", jid)
        idx = int(m.group(1)) if m else 0
        nodes[idx] = (pbs_epoch(j.get("stime")),
                      pbs_epoch(j.get("obittime") or j.get("mtime")))
    return nodes


CACHE_RE = re.compile(r"^qstat\.derecho\s+(.*\d{4})\s*$", re.M)


def read_prio(set_name, ids):
    """[(sample epoch, cache stamp, {jobid: (computed, eligible, queued subjobs, place)}, queued total)]"""
    out = []
    seen = set()
    for path in sorted(glob.glob("samples/%s/prio.*.txt" % set_name),
                       key=lambda p: int(p.split(".")[-2])):
        text = open(path).read()
        m = CACHE_RE.search(text)
        stamp = m.group(1) if m else path
        if stamp in seen:
            continue
        seen.add(stamp)
        place, ours = 0, {}
        for line in text.splitlines():
            f = line.split()
            if len(f) != 14 or not f[0][0].isdigit():
                continue
            jid, state = f[0], f[4]
            if state == "Q":
                place += 1
            if jid in ids:
                ours[jid] = (float(f[5]), float(f[10]), f[11], place if state == "Q" else None)
        out.append((int(path.split(".")[-2]), stamp, ours, place))
    return out


def node_seconds(set_name, run):
    """Each node's time as launch_cf reports it, summed, and steps ok / run."""
    total, ok, ran = 0, 0, 0
    for path in glob.glob("*.o%s*" % jobnum(run["jobid"])):
        text = open(path).read()
        m = re.search(r"took (\d+) seconds", text)
        if m:
            total += int(m.group(1))
        ok += len(re.findall(r"finished  step \d+: exit status 0$", text, re.M))
        ran += len(re.findall(r"finished  step \d+: exit status", text))
    return total, ok, ran


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    set_name = sys.argv[1]
    runs = sorted(read_runs(set_name), key=lambda r: -int(r["nodes"]))
    ids = {r["jobid"]: r for r in runs}
    prio = read_prio(set_name, ids)

    hdr = "%5s %5s %7s | %15s %7s | %11s | %20s %6s | %7s %7s %7s" % (
        "nodes", "waves", "wall", "prio: first max", "age s", "place: 1st best",
        "wait s: first med last", "done s", "node-s", "nodes", "run s") + "  steps ok"
    print(hdr)
    print("-" * len(hdr))
    for r in runs:
        sub = int(r["submit_epoch"])
        seen = [s[2][r["jobid"]] for s in prio if r["jobid"] in s[2]]
        queued = [x for x in seen if x[3] is not None]
        p_first = "%.2f" % queued[0][0] if queued else "-"
        p_max = "%.2f" % max(x[0] for x in queued) if queued else "-"
        age = "%.0f" % queued[-1][1] if queued else "-"
        pl_first = str(queued[0][3]) if queued else "-"
        pl_best = str(min(x[3] for x in queued)) if queued else "-"
        nodes = read_final(set_name, r)
        if nodes:
            starts = sorted(s for s, e in nodes.values() if s)
            ends = [e for s, e in nodes.values() if e]
            waits = [s - sub for s in starts]
            wait = "%6.0f %6.0f %6.0f" % (waits[0], st.median(waits), waits[-1]) if waits else "-"
            done = "%.0f" % (max(ends) - sub) if ends else "-"
            runs_s = "%.0f" % (max(ends) - starts[0]) if ends and starts else "-"
            ndone = "%d/%d" % (len(ends), len(nodes))
        else:
            wait, done, runs_s, ndone = "(running)", "-", "-", "-"
        ns, ok, ran = node_seconds(set_name, r)
        print("%5s %5s %7s | %7s %7s %7s | %5s %5s | %20s %6s | %7s %7s %7s  %d/%d" % (
            r["nodes"], r["waves"], r["walltime"], p_first, p_max, age, pl_first, pl_best,
            wait, done, ns or "-", ndone, runs_s, ok, ran))

    if "--series" in sys.argv:
        print("\nper sample of the pbs-prio cache: queued subjobs  priority  place (of all queued cpu jobs)")
        t0 = min(int(r["submit_epoch"]) for r in runs)
        print("%7s %6s  " % ("t s", "queued") + "  ".join("%20s" % ("%sx%s" % (r["nodes"], r["waves"])) for r in runs))
        for epoch, stamp, ours, nq in prio:
            cells = []
            for r in runs:
                x = ours.get(r["jobid"])
                if x is None:
                    cells.append("%20s" % "-")
                else:
                    cells.append("%20s" % ("%s %.2f %s" % (x[2], x[0], x[3] if x[3] else "run")))
            print("%7d %6d  " % (epoch - t0, nq) + "  ".join(cells))


if __name__ == "__main__":
    main()
