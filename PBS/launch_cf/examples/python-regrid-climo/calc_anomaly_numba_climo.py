#!/usr/bin/env python3
"""
calc_anomaly_numba_climo.py
The anomaly kernel on one ERA5 day, against a LONG-TERM climatology, in ONE
pass over the file.

calc_anomaly_numba_pario.py measures each hour against the mean of its own
day, so it has to read the whole file once to get that mean and again to
compute (or keep the whole decompressed day in memory, --keep).  Here the
reference is the 1991-2020 mean of the same calendar day, computed once
beforehand by make_climo.sh, so each hour is read, decompressed and used
straight away:

  1. read the calendar day's climatology (one uncompressed 3D field,
     154 MB, written by make_climo_day.py) with h5py into the float32
     staging buffer, and copy it into climo_3d over the first-touch row
     bands;
  2. for each hour: read and inflate its chunk on the I/O threads, undo the
     shuffle, and run the kernel of calc_anomaly_numba.py -- exactly
     calc_anomaly_numba_pario.py's pass 2.

With --h5py, step 2 instead reads each hour with h5py's read_direct, as
calc_anomaly_numba_io.py does: HDF5 inflates and unshuffles on the main
thread only, one hour at a time, while the Numba threads wait.  The two
readers give the same Checksum.

The kernels, decompression and first-touch layout are those of
calc_anomaly_numba_io.py and calc_anomaly_numba_pario.py, the two-pass
scripts in this directory.
"""
import os
import re
import socket
import time

# calc_anomaly_numba_io sets NUMBA_NUM_THREADS from OMP_NUM_THREADS on import
from calc_anomaly_numba_io import (
    accumulate_climo, allocate, arg_parser, ingest_and_compute_step, warm_up,
)
from calc_anomaly_numba_pario import chunk_locations, inflated_steps, unshuffle
import h5py
import numpy as np
from numba import get_num_threads

DAY_RE = re.compile(r"\.(\d{4})(\d{2})(\d{2})00_\d{10}\.nc$")


def main():
    parser = arg_parser("Numba anomaly kernel on one ERA5 file against a long-term climatology")
    parser.add_argument("--climo", default="climo/T_1991-2020_{mmdd}.h5",
                        help="climatology file; {mmdd} becomes the file's calendar day")
    parser.add_argument("--io-threads", type=int, default=0,
                        help="Decompression threads (0 = the Numba thread count)")
    parser.add_argument("--h5py", action="store_true",
                        help="Read each hour with h5py (HDF5 decompresses on one thread) "
                             "instead of the parallel decompression")
    args = parser.parse_args()
    warm_up()

    m = DAY_RE.search(args.file)
    if not m:
        raise SystemExit(f"can't tell the day from the file name {args.file}")
    climo_path = args.climo.format(mmdd=m.group(2) + m.group(3))

    with h5py.File(args.file, "r") as f:
        var = f[args.var]                   # (time, level, latitude, longitude)
        shape_3d = var.shape[1:]
        dtype = var.dtype
        ntime = var.shape[0] if args.nsteps <= 0 else min(args.nsteps, var.shape[0])
        locs = chunk_locations(var, ntime)

    nlev, nlat, nlon = shape_3d
    itemsize = dtype.itemsize
    nbytes = nlev * nlat * nlon * itemsize
    nio = args.io_threads if args.io_threads > 0 else get_num_threads()

    t0 = time.perf_counter()
    temp_3d, climo_3d, out_3d, weights = allocate(shape_3d)   # zeroed, first-touched
    io_buf = np.empty(shape_3d, dtype=dtype)
    io_u8 = io_buf.reshape(-1).view(np.uint8)
    t_alloc = time.perf_counter() - t0

    t_start = time.perf_counter()
    # 1. the long-term climatology of this calendar day -> climo_3d
    with h5py.File(climo_path, "r") as f:
        c = f[args.var]
        if c.shape != shape_3d:
            raise SystemExit(f"{climo_path}: shape {c.shape}, expected {shape_3d}")
        c.read_direct(io_buf)
    accumulate_climo(io_buf, climo_3d, 1.0)
    t_climo = time.perf_counter() - t_start

    # 2. one pass: every hour read, decompressed and used once
    t_wait = t_unsh = t_comp = 0.0
    checksum = 0.0
    if args.h5py:
        # HDF5 reads, inflates and unshuffles each hour on this thread
        with h5py.File(args.file, "r") as f:
            var = f[args.var]
            for t in range(ntime):
                t1 = time.perf_counter()
                var.read_direct(io_buf, source_sel=np.s_[t])
                t2 = time.perf_counter()
                ingest_and_compute_step(io_buf, temp_3d, climo_3d, out_3d, weights)
                checksum += float(np.mean(out_3d[1:-1, ::60, ::60])) / ntime
                t_wait += t2 - t1
                t_comp += time.perf_counter() - t2
    else:
        for t, raw, wait in inflated_steps(args.file, locs, nio, nbytes):
            t1 = time.perf_counter()
            unshuffle(np.frombuffer(raw, dtype=np.uint8), io_u8, nlev, nlat, nlon, itemsize)
            del raw
            t2 = time.perf_counter()
            ingest_and_compute_step(io_buf, temp_3d, climo_3d, out_3d, weights)
            checksum += float(np.mean(out_3d[1:-1, ::60, ::60])) / ntime
            t_wait += wait
            t_unsh += t2 - t1
            t_comp += time.perf_counter() - t2
    t_total = time.perf_counter() - t_start

    # uncompressed data used, and the Numba part's memory traffic per hour:
    # copy = read io_buf, write temp_3d (+ write-allocate); kernel = read
    # temp_3d + climo_3d, write out_3d (+ write-allocate)
    gb_data = (ntime + 1) * io_buf.nbytes / 1e9
    gb_moved = ntime * (io_buf.nbytes + 6 * temp_3d.nbytes) / 1e9
    if args.h5py:
        label, threads_txt = "climo-h5py", ""
        timers_txt = f"Read: {t_wait:.2f}s"
    else:
        label, threads_txt = "climo", f" | IO threads: {nio:2d}"
        timers_txt = f"Wait: {t_wait:.2f}s | Unshuffle: {t_unsh:.2f}s"
    print(
        f"[{label} {args.member:03d} | Host: {socket.gethostname()} | "
        f"Threads: {get_num_threads():2d}{threads_txt}] "
        f"Steps: 1 x {ntime} x {nlev}x{nlat}x{nlon} | Alloc: {t_alloc:.2f}s | "
        f"Climo: {t_climo:.2f}s | {timers_txt} | "
        f"Compute: {t_comp:.2f}s | Total: {t_total:.2f}s ({gb_data / t_total:4.2f} GB/s) | "
        f"Compute BW: {gb_moved / t_comp:5.1f} GB/s | Checksum: {checksum:.4f}"
    )

if __name__ == "__main__":
    main()
