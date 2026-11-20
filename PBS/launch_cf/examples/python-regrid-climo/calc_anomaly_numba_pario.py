#!/usr/bin/env python3
"""
calc_anomaly_numba_pario.py
calc_anomaly_numba_io.py with PARALLEL decompression.

HDF5 decompresses on one thread, and for ERA5 that is most of the run time:
~0.5 s per time step, against ~0.02-0.08 s for the Numba kernel.  This script
does HDF5's job itself so that several time steps decompress at once:

  1. h5py is used only to find where each time step's compressed chunk sits
     in the file (one chunk per time step in ERA5) and to check that the
     filters are the expected shuffle + deflate.
  2. A pool of I/O threads, each with a time step of its own, reads the
     chunk's bytes with os.pread() and inflates them with zlib.decompress().
     Both release the Python GIL, so the threads really run in parallel.
     They work up to --io-threads steps ahead of the computation.
  3. In the main thread, a Numba kernel undoes the HDF5 shuffle filter (which
     stores byte 0 of every value, then byte 1, ...) into the float32 io_buf,
     over the same latitude bands as everything else, and the unchanged
     kernels from calc_anomaly_numba_io.py take over.

Like calc_anomaly_numba_io.py it makes two passes, daily mean then anomaly,
so the pipeline of steps 2 and 3 runs twice.  With --keep, pass 1 unshuffles
every time step into an array of its own and keeps it, and pass 2 computes
from those arrays: each chunk is decompressed once, for about 3.7 GB more
memory per ERA5 file.

The kernels, the first-touch layout and the output line are those of
calc_anomaly_numba_io.py, so the two scripts differ only in how the data
is read.  The Checksum must agree between them.
"""
import os
import time
import zlib
from concurrent.futures import ThreadPoolExecutor

# calc_anomaly_numba_io sets NUMBA_NUM_THREADS from OMP_NUM_THREADS on import
from calc_anomaly_numba_io import (
    accumulate_climo, allocate, arg_parser, ingest_and_compute_step, report, warm_up,
)
import h5py
import numpy as np
from numba import njit, prange, get_num_threads


@njit(fastmath=True, cache=True)
def _unshuffle_row(raw, io_u8, j, nlev, nlat, nlon, itemsize):
    """Undo the shuffle filter for latitude row j of every level."""
    n = nlev * nlat * nlon
    for k in range(nlev):
        base = (k * nlat + j) * nlon
        for i in range(nlon):
            e = base + i
            for b in range(itemsize):
                io_u8[e * itemsize + b] = raw[b * n + e]


@njit(parallel=True, fastmath=True, cache=True)
def unshuffle(raw, io_u8, nlev, nlat, nlon, itemsize):
    """
    raw:   the inflated chunk, bytes grouped by byte position (shuffle filter)
    io_u8: io_buf viewed as bytes, written in normal element order

    The rows are split with the same prange(1, nlat - 1) as the other
    kernels, so each thread writes the part of io_buf it copies next.
    """
    for j in prange(1, nlat - 1):
        _unshuffle_row(raw, io_u8, j, nlev, nlat, nlon, itemsize)
    _unshuffle_row(raw, io_u8, 0, nlev, nlat, nlon, itemsize)
    _unshuffle_row(raw, io_u8, nlat - 1, nlev, nlat, nlon, itemsize)


def chunk_locations(var, ntime):
    """(offset, size) in the file of the compressed chunk of each time step."""
    shape_3d = var.shape[1:]
    if var.chunks != (1,) + shape_3d:
        raise SystemExit(f"expected one chunk per time step, got chunks={var.chunks}")

    plist = var.id.get_create_plist()
    filters = [plist.get_filter(i)[0] for i in range(plist.get_nfilters())]
    if filters != [h5py.h5z.FILTER_SHUFFLE, h5py.h5z.FILTER_DEFLATE]:
        raise SystemExit(f"expected shuffle + deflate filters, got {filters}")
    if not var.dtype.isnative:
        raise SystemExit(f"expected native byte order, got {var.dtype}")

    locs = []
    for t in range(ntime):
        info = var.id.get_chunk_info_by_coord((t,) + (0,) * len(shape_3d))
        if info.filter_mask != 0:
            raise SystemExit(f"chunk {t} skips a filter (mask {info.filter_mask})")
        locs.append((info.byte_offset, info.size))
    return locs


def inflated_steps(path, locs, nio, nbytes):
    """
    Yield (t, raw, wait) for t = 0, 1, ... in order: raw is time step t's
    chunk, read and inflated by a pool of nio threads that keep nio steps in
    flight; wait is how long the caller was blocked waiting for it.
    """
    fd = os.open(path, os.O_RDONLY)

    def read_and_inflate(t):
        offset, size = locs[t]
        return zlib.decompress(os.pread(fd, size, offset), bufsize=nbytes)

    try:
        with ThreadPoolExecutor(max_workers=nio) as pool:
            ntime = len(locs)
            pending = {t: pool.submit(read_and_inflate, t) for t in range(min(nio, ntime))}
            for t in range(ntime):
                t0 = time.perf_counter()
                raw = pending.pop(t).result()
                if t + nio < ntime:
                    pending[t + nio] = pool.submit(read_and_inflate, t + nio)
                yield t, raw, time.perf_counter() - t0
                del raw
    finally:
        os.close(fd)


def main():
    parser = arg_parser("Numba anomaly kernel on one ERA5 file, parallel decompression")
    parser.add_argument("--io-threads", type=int, default=0,
                        help="Decompression threads (0 = the Numba thread count)")
    parser.add_argument("--keep", action="store_true",
                        help="Keep every time step decompressed after pass 1, so pass 2 "
                             "reads from memory (about 3.7 GB more for an ERA5 day)")
    args = parser.parse_args()
    warm_up()

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

    # compile (or load) the unshuffle kernel; raw arrays come from bytes, so read-only
    unshuffle(np.frombuffer(bytes(4 * 8), dtype=np.uint8), np.empty(4 * 8, np.uint8),
              1, 4, 2, 4)

    t0 = time.perf_counter()
    temp_3d, climo_3d, out_3d, weights = allocate(shape_3d)
    io_buf = np.empty(shape_3d, dtype=dtype)   # first-touched by unshuffle
    io_u8 = io_buf.reshape(-1).view(np.uint8)
    t_alloc = time.perf_counter() - t0

    if args.keep:
        # every time step stays decompressed: (ntime, nlev, nlat, nlon) float32,
        # 3.69 GB for an ERA5 day, first-touched by unshuffle like io_buf
        kept = np.empty((ntime,) + tuple(shape_3d), dtype=dtype)
        kept_u8 = kept.reshape(ntime, -1).view(np.uint8)

    t_wait = 0.0     # main thread blocked waiting for a decompressed step
    t_unsh = 0.0     # Numba unshuffle into io_buf
    t_comp = 0.0     # Numba kernels
    checksum = 0.0
    t_start = time.perf_counter()

    # pass 1: climo_3d = mean over the time steps
    for t, raw, wait in inflated_steps(args.file, locs, nio, nbytes):
        buf, buf_u8 = (kept[t], kept_u8[t]) if args.keep else (io_buf, io_u8)
        t1 = time.perf_counter()
        unshuffle(np.frombuffer(raw, dtype=np.uint8), buf_u8, nlev, nlat, nlon, itemsize)
        del raw
        t2 = time.perf_counter()
        accumulate_climo(buf, climo_3d, 1.0 / ntime)
        t_wait += wait
        t_unsh += t2 - t1
        t_comp += time.perf_counter() - t2

    # pass 2: anomaly kernel on every time step, from memory with --keep,
    # otherwise read and decompressed again
    if args.keep:
        steps = ((t, kept[t]) for t in range(ntime))
    else:
        steps = inflated_steps(args.file, locs, nio, nbytes)
    for item in steps:
        if args.keep:
            t, buf = item
        else:
            t, raw, wait = item
            t1 = time.perf_counter()
            unshuffle(np.frombuffer(raw, dtype=np.uint8), io_u8, nlev, nlat, nlon, itemsize)
            del raw
            t_wait += wait
            t_unsh += time.perf_counter() - t1
            buf = io_buf
        t2 = time.perf_counter()
        ingest_and_compute_step(buf, temp_3d, climo_3d, out_3d, weights)
        checksum += float(np.mean(out_3d[1:-1, ::60, ::60])) / ntime
        t_comp += time.perf_counter() - t2
    t_total = time.perf_counter() - t_start

    report("pario", args, ntime, shape_3d, t_alloc, t_total,
           {"Wait": t_wait, "Unshuffle": t_unsh, "Compute": t_comp}, checksum,
           temp_3d.nbytes, io_buf.nbytes,
           extra=f" | IO threads: {nio:2d}" + (" | keep" if args.keep else ""))


if __name__ == "__main__":
    main()
