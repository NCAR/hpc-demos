#!/usr/bin/env python3
"""Parse step-*.out files in a directory into a CSV.

Usage: parse_steps.py <directory> [-o output.csv] [--lscpu lscpu.txt]

Each step-*.out file is expected to contain a line like:
    step 1 | host dec2452 | core 229 | thread 0 of 1 | PBS_ARRAY_INDEX=0

If an lscpu.txt file (output of `lscpu`) is available, it is used to map
each hardware thread ("core" above, i.e. a Linux CPU id) to its physical
core, based on the "NUMA node<N> CPU(s):" lines and "Thread(s) per core:".
"physical core" and "numa domain" columns are added to the CSV, and usage is
summarized per PBS array index: how many physical cores the index's threads
landed on, how many of those cores took more than one thread, and how many
cores of the node went unused.  Pass --details to also list the reused cores.

Every thread of every step is recorded, so a multi-threaded step produces one
row per thread.  For those runs the summary also reports how many steps kept
all of their threads inside a single NUMA domain -- the difference between a
command file whose steps are prefixed with "numactl --cpunodebind=N" and one
that leaves placement to the Linux scheduler.

The summary is per array index because each index is one node's worth of
work.  Two indices may report the same host, but they ran at different
times on a node that was released and reallocated in between, so cores
"shared" between two indices were never actually in contention.
"""
import argparse
import csv
import glob
import os
import re
import sys
from collections import defaultdict

LINE_RE = re.compile(
    r"step\s+(?P<step>\d+)\s*\|\s*"
    r"host\s+(?P<host>\S+)\s*\|\s*"
    r"core\s+(?P<core>\d+)\s*\|\s*"
    r"thread\s+(?P<thread>\d+)\s+of\s+\d+\s*\|\s*"
    r"PBS_ARRAY_INDEX=(?P<array_index>\d+)"
)

THREADS_PER_CORE_RE = re.compile(r"Thread\(s\) per core:\s*(\d+)")
NUMA_NODE_RE = re.compile(r"NUMA node\d+ CPU\(s\):\s*(\S+)")


def expand_range(range_str):
    """Expand a single 'a-b' or 'a' token into a list of ints."""
    if "-" in range_str:
        lo, hi = range_str.split("-")
        return list(range(int(lo), int(hi) + 1))
    return [int(range_str)]


def parse_lscpu(path):
    """Build a mapping of CPU id -> physical core id from lscpu output.

    Each 'NUMA node<N> CPU(s):' line lists comma-separated ranges, one
    range per hardware thread slot (as many ranges as Thread(s) per
    core). Ranges are parallel: the CPU at position i in each range is
    a sibling hardware thread of the same physical core, identified
    here by the CPU id at position i of the first range.
    """
    threads_per_core = None
    node_lines = []
    with open(path) as f:
        for line in f:
            m = THREADS_PER_CORE_RE.search(line)
            if m:
                threads_per_core = int(m.group(1))
            m = NUMA_NODE_RE.search(line)
            if m:
                node_lines.append(m.group(1))

    if threads_per_core is None or not node_lines:
        raise ValueError(f"could not find NUMA/thread info in {path}")

    cpu_to_physical = {}
    cpu_to_numa = {}
    for domain, cpu_list in enumerate(node_lines):
        ranges = [expand_range(tok) for tok in cpu_list.split(",")]
        if len(ranges) != threads_per_core:
            raise ValueError(
                f"expected {threads_per_core} CPU ranges (Thread(s) per core) "
                f"but found {len(ranges)} in '{cpu_list}'"
            )
        core_count = len(ranges[0])
        for pos in range(core_count):
            physical = ranges[0][pos]
            for r in ranges:
                cpu_to_physical[r[pos]] = physical
                cpu_to_numa[r[pos]] = domain
    return cpu_to_physical, cpu_to_numa


def parse_file(path):
    """Return one dict per matching line -- i.e. one per thread of the step."""
    found = []
    with open(path) as f:
        for line in f:
            m = LINE_RE.search(line)
            if m:
                found.append(m.groupdict())
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", help="Directory containing step-*.out files")
    parser.add_argument(
        "-o", "--output", default="steps.csv", help="Output CSV path (default: steps.csv)"
    )
    parser.add_argument(
        "--lscpu",
        default="lscpu.txt",
        help="Path to lscpu output used to map cores to physical cores (default: lscpu.txt)",
    )
    parser.add_argument(
        "--details",
        action="store_true",
        help="List the individual reused cores, not just the per-index counts",
    )
    args = parser.parse_args()

    pattern = os.path.join(args.directory, "step-*.out")
    files = sorted(glob.glob(pattern))
    if not files:
        print(f"No files matching {pattern}", file=sys.stderr)
        sys.exit(1)

    cpu_to_physical = cpu_to_numa = None
    if os.path.exists(args.lscpu):
        cpu_to_physical, cpu_to_numa = parse_lscpu(args.lscpu)
    else:
        print(
            f"warning: {args.lscpu} not found, skipping physical core mapping",
            file=sys.stderr,
        )

    rows = []
    for path in files:
        found = parse_file(path)
        if not found:
            print(f"warning: no match found in {path}", file=sys.stderr)
            continue
        for parsed in found:
            parsed["physical_core"] = ""
            parsed["numa_domain"] = ""
            if cpu_to_physical is not None:
                core = int(parsed["core"])
                if core not in cpu_to_physical:
                    print(
                        f"warning: core {core} in {path} not found in {args.lscpu}",
                        file=sys.stderr,
                    )
                else:
                    parsed["physical_core"] = cpu_to_physical[core]
                    parsed["numa_domain"] = cpu_to_numa[core]
            rows.append(parsed)

    fieldnames = ["step", "host", "core", "thread", "array_index", "physical_core", "numa_domain"]
    with open(args.output, "w", newline="") as out:
        writer = csv.DictWriter(out, fieldnames=fieldnames)
        writer.writerow(
            {
                "step": "step number",
                "host": "host name",
                "core": "core number",
                "thread": "thread",
                "array_index": "array index",
                "physical_core": "physical core",
                "numa_domain": "numa domain",
            }
        )
        writer.writerows(rows)

    print(f"Wrote {len(rows)} rows to {args.output}")

    if cpu_to_physical is None:
        return

    cores_per_node = len(set(cpu_to_physical.values()))
    summarize(rows, cores_per_node, args.details)


def summarize(rows, cores_per_node, show_details):
    """Report physical core usage, one line per PBS array index.

    Each array index is one node's worth of steps, so "did two steps land on
    the same physical core?" is only a meaningful question within a single
    index.  Steps from different indices that report the same host ran at
    different times, on a node released and reallocated in between.
    """
    by_index = defaultdict(list)
    for row in rows:
        if row["physical_core"] != "":
            by_index[row["array_index"]].append(row)

    if not by_index:
        return

    # a step contributes one row per thread; threaded runs get the NUMA column
    threads_per_step = max(
        len([r for r in rows if r["array_index"] == i and r["step"] == st])
        for i in by_index
        for st in {r["step"] for r in by_index[i]}
    )
    threaded = threads_per_step > 1

    print()
    print(f"Physical core usage per array index ({cores_per_node} cores/node):")
    print()
    head = f"  {'index':>5}  {'host':<10}  {'steps':>5}  {'thrds':>5}  {'used':>5}  {'reused':>6}  {'unused':>6}"
    rule = f"  {'-'*5}  {'-'*10}  {'-'*5}  {'-'*5}  {'-'*5}  {'-'*6}  {'-'*6}"
    if threaded:
        head += f"  {'1-dom':>5}  {'maxdom':>6}"
        rule += f"  {'-'*5}  {'-'*6}"
    print(head)
    print(rule)

    reused_by_index = {}
    spanning = {}
    for index in sorted(by_index, key=int):
        index_rows = by_index[index]

        threads_per_core = defaultdict(list)
        for row in index_rows:
            threads_per_core[row["physical_core"]].append(row["step"])

        reused = {c: s for c, s in threads_per_core.items() if len(s) > 1}
        reused_by_index[index] = reused

        used = len(threads_per_core)
        unused = cores_per_node - used
        hosts = ",".join(sorted({row["host"] for row in index_rows}))

        # which NUMA domains did each step's threads land in, and how many
        # threads in each?
        domains_per_step = defaultdict(lambda: defaultdict(int))
        for row in index_rows:
            if row["numa_domain"] != "":
                domains_per_step[row["step"]][row["numa_domain"]] += 1
        steps = len(domains_per_step) or len({r["step"] for r in index_rows})
        confined = sum(1 for d in domains_per_step.values() if len(d) == 1)
        max_domains = max((len(d) for d in domains_per_step.values()), default=0)
        spanning[index] = {st: d for st, d in domains_per_step.items() if len(d) > 1}

        line = (
            f"  {index:>5}  {hosts:<10}  {steps:>5}  {len(index_rows):>5}  {used:>5}  "
            f"{len(reused):>6}  {unused:>6}"
        )
        if threaded:
            line += f"  {confined:>5}  {max_domains:>6}"
        print(line)

    print()
    print("  thrds  = thread records, i.e. steps x threads/step")
    print("  used   = distinct physical cores the index's threads reported")
    print("  reused = those cores that took more than one thread")
    print("  unused = cores of the node no thread reported")
    if threaded:
        print("  1-dom  = steps whose threads all stayed in one NUMA domain;")
        print("           this is what \"numactl --cpunodebind\" buys you")
        print("  maxdom = most NUMA domains any single step's threads were spread over")

    # A node can serve more than one array index, sequentially.  Say so, since
    # it explains why the same host appears on several lines above.
    indices_per_host = defaultdict(list)
    for index in sorted(by_index, key=int):
        for host in sorted({row["host"] for row in by_index[index]}):
            indices_per_host[host].append(index)
    shared = {h: i for h, i in indices_per_host.items() if len(i) > 1}
    if shared:
        print()
        print("  note: these nodes served more than one array index, sequentially:")
        for host, indices in sorted(shared.items()):
            print(f"          {host} -> indices {', '.join(indices)}")
        print("        Those indices ran at different times, on a node released and")
        print("        reallocated in between, so cores they share were not contended.")

    if threaded:
        total_spanning = sum(len(v) for v in spanning.values())
        print()
        if total_spanning == 0:
            print("  Every step kept all of its threads inside a single NUMA domain.")
        else:
            print(f"  {total_spanning} step(s) spread threads over more than one NUMA domain:")
            print()
            print(f"    {'index':>5}  {'step':>5}  {'doms':>4}  threads per domain")
            print(f"    {'-'*5}  {'-'*5}  {'-'*4}  {'-'*40}")
            for index in sorted(spanning, key=int):
                for step in sorted(spanning[index], key=int):
                    counts = spanning[index][step]
                    spread = " ".join(
                        f"d{d}:{counts[d]}" for d in sorted(counts, key=int)
                    )
                    print(f"    {index:>5}  {step:>5}  {len(counts):>4}  {spread}")

    if show_details:
        for index in sorted(reused_by_index, key=int):
            reused = reused_by_index[index]
            if not reused:
                continue
            print()
            print(f"  array index {index}, {len(reused)} reused core(s):")
            for core in sorted(reused, key=int):
                steps = reused[core]
                print(f"    physical core {core:>3}: {len(steps)} steps ({', '.join(steps)})")


if __name__ == "__main__":
    main()
