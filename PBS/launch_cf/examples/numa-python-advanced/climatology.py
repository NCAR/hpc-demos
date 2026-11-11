#!/usr/bin/env python3
"""
Threaded mean and standard deviation of one ERA5 field, reporting where its
threads ran and where its memory lives.

The array is split into latitude bands, one per thread, and every thread
repeatedly computes the time mean and standard deviation of its own band with
NumPy.  NumPy releases the GIL inside each call, so the threads really do run
at once.  One call of mean_std() on a band is a "pass": it reads the band
twice, doing about one flop per value read, so its speed is set by memory
bandwidth, not arithmetic.  That is the kind of work NUMA placement affects.
The result is the same every pass and is discarded; the repeats only make the
computing long enough to time (see "The computation" in README.md).

Each run has three phases:

  load      read the field from NetCDF (or a .npy cache) on the main thread;
            not timed, so neither GLADE nor the HDF5 lock is measured
  compute   every thread loops over its band, for --seconds seconds or for
            --passes passes
  report    one line: throughput, and where the threads ran and the memory is

--seconds gives every run the same length, which suits a benchmark (see
numa_test.sh).  --passes gives every run the same work, as a launch_cf step
has, so a slower placement shows up as a longer step (see run_step.sh).

With --sync, several copies started together on one node load first and then
start computing at the same moment, so their compute phases overlap and they
compete for memory bandwidth, as the steps of a full launch_cf node do.

Placement options:

  --first-touch main     the main thread reads the whole field, so Linux puts
                         every page in the NUMA domain that thread was on (the
                         default, and what most real scripts do)
  --first-touch threads  each thread copies its own band, so that band's pages
                         go where that thread was running when it copied them
  --pin-threads          each thread pins itself to one CPU of the process's
                         allowed set (a Python version of OMP_PROC_BIND=close)

Run it under numactl to restrict the CPUs and memory policy from outside.

Output is one line of key=value fields, e.g.

  variant=bind step=3 host=dec0001 index=- cpus=48-63,176-191
  threads_on=D3:100 memory_on=D3:100 local=100 load_s=2.1 seconds=20.0
  GBps=35.2 s_per_pass=0.176

index       PBS_ARRAY_INDEX, so steps can be grouped by the node they shared
load_s      seconds to load the field (not part of GBps)
seconds     length of the compute phase, to the slowest thread
threads_on  share of the threads' CPU samples on each NUMA domain (%)
memory_on   share of the array's sampled pages on each NUMA domain (%)
local       share of a thread's samples on the domain holding its own band (%)
GBps        array bytes read per second, all threads together
s_per_pass  seconds per mean+stddev of the whole array at that rate

Examples:
  python3 climatology.py --file e5.oper.an.sfc.128_167_2t.ll025sc.2020010100_2020013123.nc
  python3 climatology.py --synthetic 200 --threads 4 --seconds 5
  numactl --cpunodebind=3 --membind=3 python3 climatology.py --cache /dev/shm/2t.npy
"""

import os

# These must be set before NumPy is imported.  One thread per NumPy call means
# the only threads are the ones this script starts.  npl's NumPy uses BLIS;
# the others cover NumPy builds on OpenBLAS or MKL, and numexpr.
for _var in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
             "BLIS_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
    os.environ[_var] = "1"

import argparse
import collections
import ctypes
import glob
import platform
import socket
import sys
import threading
import time

import numpy as np

# time steps per NumPy call: 8 steps of one band are ~2 MB, so the scratch
# array for the anomalies stays in cache and the big array is all that streams
CHUNK = 8

try:
    _libc = ctypes.CDLL(None, use_errno=True)
    _sched_getcpu = _libc.sched_getcpu
except (OSError, AttributeError):        # not Linux
    _libc = _sched_getcpu = None


# ---------------------------------------------------------------- topology

def cpu_ranges(cpus):
    """[0, 1, 2, 5] -> '0-2,5'"""
    cpus = sorted(cpus)
    if not cpus:
        return "?"
    out, start = [], cpus[0]
    for prev, cur in zip(cpus, cpus[1:] + [None]):
        if cur != prev + 1:
            out.append(f"{start}" if start == prev else f"{start}-{prev}")
            start = cur
    return ",".join(out)


def cpu_domains():
    """{cpu: NUMA domain}, from sysfs; empty where there is no sysfs."""
    domain = {}
    for path in glob.glob("/sys/devices/system/node/node[0-9]*/cpulist"):
        node = int(path.split("/")[-2][4:])
        with open(path) as f:
            for part in f.read().strip().split(","):
                if not part:
                    continue
                lo, _, hi = part.partition("-")
                for cpu in range(int(lo), int(hi or lo) + 1):
                    domain[cpu] = node
    return domain


def allowed_cpus():
    try:
        return sorted(os.sched_getaffinity(0))
    except AttributeError:               # not Linux
        return []


def current_cpu():
    return _sched_getcpu() if _sched_getcpu else -1


def page_domains(addresses):
    """NUMA domain of the page holding each address, or [] if unknown.

    move_pages(2) with no target nodes moves nothing; it reports where each
    page is.  Called through syscall() so that libnuma is not needed.
    """
    if _libc is None or platform.machine() != "x86_64" or not addresses:
        return []
    page = os.sysconf("SC_PAGE_SIZE")
    n = len(addresses)
    pages = (ctypes.c_void_p * n)(*[a - a % page for a in addresses])
    status = (ctypes.c_int * n)()
    SYS_move_pages = 279                 # x86_64
    rc = _libc.syscall(ctypes.c_long(SYS_move_pages), ctypes.c_int(0),
                       ctypes.c_ulong(n), pages, None, status, ctypes.c_int(0))
    if rc != 0:
        return []
    return [s for s in status if s >= 0]  # negative = not resident, etc.


def band_addresses(band, n=32):
    """Addresses spread over a (time, lat, lon) band, one per sampled time."""
    times = np.linspace(0, band.shape[0] - 1, min(n, band.shape[0])).astype(int)
    return [band[t].ctypes.data for t in times]


def shares(counter):
    """Counter -> 'D0:75,D3:25' (percent, largest first)."""
    total = sum(counter.values())
    if not total:
        return "?"
    return ",".join(f"D{k}:{round(100 * v / total)}"
                    for k, v in counter.most_common())


# ---------------------------------------------------------------- data

def load(args):
    """The field as a C-ordered float32 (time, lat, lon) array."""
    if args.cache and os.path.exists(args.cache):
        return np.load(args.cache)
    if args.synthetic:                   # ERA5's 0.25 degree grid
        rng = np.random.default_rng(0)
        x = rng.random((args.synthetic, 721, 1440), dtype=np.float32)
        x *= 30.0
        x += 273.0
    elif args.file:
        import netCDF4                   # only needed when reading NetCDF
        with netCDF4.Dataset(args.file) as ds:
            if args.var:
                var = ds.variables[args.var]
            else:                        # the largest variable with 3+ dims
                var = max((v for v in ds.variables.values() if v.ndim >= 3),
                          key=lambda v: v.size)
            var.set_auto_mask(False)
            print(f"read {var.name}{var.shape} from {args.file}",
                  file=sys.stderr)
            x = np.ascontiguousarray(var[:], dtype=np.float32)
        x = x.reshape((x.shape[0], -1, x.shape[-1]))   # fold any level dims
    else:
        sys.exit("ERROR: give --file, --synthetic, or an existing --cache")

    if args.cache:                       # write, then rename: never half a file
        tmp = f"{args.cache}.{os.getpid()}.tmp.npy"
        np.save(tmp, x)
        os.replace(tmp, args.cache)
    return x


# ---------------------------------------------------------------- compute

def mean_std(band, scratch):
    """Time mean and standard deviation of a (time, lat, lon) band.

    One pass: reads the band twice, once for the mean and once for the
    squared anomalies; each NumPy call handles CHUNK time steps.
    """
    nt = band.shape[0]
    total = np.zeros(band.shape[1:], np.float64)
    for t in range(0, nt, CHUNK):
        total += band[t:t + CHUNK].sum(axis=0)
    mean = (total / nt).astype(np.float32)

    sumsq = np.zeros(band.shape[1:], np.float64)
    for t in range(0, nt, CHUNK):
        chunk = band[t:t + CHUNK]
        d = scratch[:chunk.shape[0]]
        np.subtract(chunk, mean, out=d)
        np.square(d, out=d)
        sumsq += d.sum(axis=0)
    return mean, np.sqrt(sumsq / nt)


def node_barrier(sync_dir, nprocs, timeout=600):
    """Wait until nprocs processes have reached this point (a file each)."""
    open(os.path.join(sync_dir, str(os.getpid())), "w").close()
    deadline = time.monotonic() + timeout
    while len(os.listdir(sync_dir)) < nprocs:
        if time.monotonic() > deadline:
            print("WARNING: --sync timed out; starting anyway", file=sys.stderr)
            return
        time.sleep(0.01)


def main():
    p = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter)
    src = p.add_argument_group("data")
    src.add_argument("--file", help="ERA5 NetCDF file")
    src.add_argument("--var", help="variable (default: largest with 3+ dims)")
    src.add_argument("--cache", help=".npy copy: read if present (ignoring "
                     "--file and --synthetic), else written")
    src.add_argument("--synthetic", type=int, metavar="NT",
                     help="random (NT, 721, 1440) array instead of a file")
    src.add_argument("--prepare", action="store_true",
                     help="write --cache and exit without computing")
    run = p.add_argument_group("run")
    run.add_argument("--threads", type=int, default=16)
    run.add_argument("--seconds", type=float, default=20.0,
                     help="length of the compute phase (default 20)")
    run.add_argument("--passes", type=int,
                     help="passes over its band per thread, instead of "
                     "--seconds")
    run.add_argument("--first-touch", choices=("main", "threads"),
                     default="main", help="who first writes the band memory")
    run.add_argument("--pin-threads", action="store_true",
                     help="pin each thread to one CPU of the allowed set")
    run.add_argument("--sync", metavar="DIR",
                     help="node-local directory for --nprocs to meet in")
    run.add_argument("--nprocs", type=int, default=1,
                     help="processes meeting in --sync before computing")
    out = p.add_argument_group("labels for the report line")
    out.add_argument("--label", default="-")
    out.add_argument("--step", default="-")
    args = p.parse_args()

    t_load = time.monotonic()
    x = load(args)
    t_load = time.monotonic() - t_load
    if args.prepare:
        return

    allowed = allowed_cpus()
    if args.pin_threads and len(allowed) > 2 * args.threads:
        print(f"WARNING: --pin-threads with {len(allowed)} allowed CPUs pins "
              f"every copy of this script to the same {args.threads}; "
              "restrict the CPUs with numactl or taskset first", file=sys.stderr)

    bounds = np.linspace(0, x.shape[1], args.threads + 1).astype(int)
    views = [x[:, lo:hi, :] for lo, hi in zip(bounds, bounds[1:])]
    nbytes = x.nbytes
    ready = threading.Barrier(args.threads + 1)
    go = threading.Event()
    start = [0.0]
    results = [None] * args.threads

    def work(i):
        if args.pin_threads and allowed:
            os.sched_setaffinity(0, {allowed[i % len(allowed)]})  # this thread
        band = views[i]
        if args.first_touch == "threads":
            band = band.copy()           # pages land where this thread is now
        views[i] = None                  # so main's array can be freed
        scratch = np.empty((CHUNK,) + band.shape[1:], np.float32)
        ready.wait()
        go.wait()
        cpus, passes = collections.Counter(), 0
        end = start[0] + args.seconds
        while True:
            mean_std(band, scratch)
            passes += 1
            cpus[current_cpu()] += 1
            if passes == args.passes or (not args.passes
                                         and time.monotonic() >= end):
                break
        results[i] = (passes * band.nbytes, time.monotonic() - start[0], cpus,
                      collections.Counter(page_domains(band_addresses(band))))

    threads = [threading.Thread(target=work, args=(i,))
               for i in range(args.threads)]
    for t in threads:
        t.start()
    ready.wait()                         # every band is in place
    del x                                # copied bands no longer need it
    if args.sync:
        node_barrier(args.sync, args.nprocs)
    start[0] = time.monotonic()
    go.set()
    for t in threads:
        t.join()
    if args.sync:                        # everyone is long past the barrier
        try:
            os.remove(os.path.join(args.sync, str(os.getpid())))
            os.rmdir(args.sync)          # succeeds for the last one out
        except OSError:
            pass

    # report
    domain = cpu_domains()
    threads_on, memory_on = collections.Counter(), collections.Counter()
    local_samples = all_samples = 0
    for _, _, cpus, pages in results:
        n_pages = sum(pages.values())
        for cpu, n in cpus.items():
            d = domain.get(cpu, "?")
            threads_on[d] += n
            all_samples += n
            if n_pages:                  # share of this band local to cpu
                local_samples += n * pages.get(d, 0) / n_pages
        memory_on.update(pages)

    read = sum(r[0] for r in results) * 2      # a pass reads its band twice
    elapsed = max(r[1] for r in results)
    gbps = read / elapsed / 1e9
    local = (f"{round(100 * local_samples / all_samples)}"
             if memory_on and all_samples else "?")
    print(f"variant={args.label} step={args.step} "
          f"host={socket.gethostname().split('.')[0]} "
          f"index={os.environ.get('PBS_ARRAY_INDEX', '-')} "
          f"cpus={cpu_ranges(allowed)} threads_on={shares(threads_on)} "
          f"memory_on={shares(memory_on)} local={local} "
          f"load_s={t_load:.1f} seconds={elapsed:.1f} "
          f"GBps={gbps:.1f} s_per_pass={2 * nbytes / (gbps * 1e9):.3f}",
          flush=True)


if __name__ == "__main__":
    main()
