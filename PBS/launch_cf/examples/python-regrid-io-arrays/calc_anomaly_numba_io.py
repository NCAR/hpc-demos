#!/usr/bin/env python3
"""
calc_anomaly_numba_io.py
calc_anomaly_numba.py with real input: the same memory-bound anomaly +
stencil kernel, run on every time step of one ERA5 pressure-level file
(GDEX dataset d633000, e5.oper.an.pl) instead of on synthetic arrays.

Each ERA5 file holds one variable for one day: (time=24, level=37,
latitude=721, longitude=1440), float32, stored as one zlib-compressed HDF5
chunk per time step.  The script makes two passes over the file:

  pass 1  climo_3d = mean over the file's time steps (the daily mean)
  pass 2  for each time step: anomaly + vertical difference + 5-point
          stencil against that daily mean (the kernel of calc_anomaly_numba.py)

so every time step is read, and decompressed, twice.

Reading keeps first-touch NUMA placement intact:

  * h5py read_direct() decompresses each time step into ONE reusable float32
    staging buffer (io_buf).  HDF5 does that on the main thread only, so
    io_buf lives in the main thread's NUMA domain -- but it is reused, and
    nothing computes on it.
  * The working arrays temp_3d, climo_3d, out_3d are float64 and first-touched
    in parallel, row band by row band, exactly as in calc_anomaly_numba.py.
  * Each step copies io_buf into temp_3d inside a prange over the SAME
    latitude bands, so every thread writes and then computes on pages in its
    own domain.

calc_anomaly_numba_pario.py imports everything here and replaces only the
h5py read with parallel decompression.

The compiled functions are cached (cache=True) in __pycache__ next to this
script, so only the first run after a change pays for compiling them.
"""
import argparse
import os
import socket
import time

# Bridge OMP_NUM_THREADS -> NUMBA_NUM_THREADS before importing numba
if "OMP_NUM_THREADS" in os.environ and "NUMBA_NUM_THREADS" not in os.environ:
    os.environ["NUMBA_NUM_THREADS"] = os.environ["OMP_NUM_THREADS"]

import h5py
import numpy as np
from numba import njit, prange, get_num_threads

ERA5_T_FILE = (
    "/glade/campaign/collections/gdex/data/d633000/e5.oper.an.pl/202301/"
    "e5.oper.an.pl.128_130_t.ll025sc.2023010100_2023010123.nc"
)


@njit(fastmath=True, cache=True)
def _zero_row(temp_3d, climo_3d, out_3d, j):
    """Zero latitude row j of every level."""
    nlev, nlat, nlon = temp_3d.shape
    for k in range(nlev):
        for i in range(nlon):
            temp_3d[k, j, i] = 0.0
            climo_3d[k, j, i] = 0.0
            out_3d[k, j, i] = 0.0


@njit(parallel=True, fastmath=True, cache=True)
def parallel_first_touch_init(temp_3d, climo_3d, out_3d, weights):
    """
    Faults the working arrays into physical RAM in parallel (first touch).

    The interior rows are split over the threads with the same
    prange(1, nlat - 1) used by every kernel below, so each thread
    first-touches the latitude band it will later copy into and compute on.
    """
    nlev, nlat, nlon = temp_3d.shape

    for k in range(nlev):
        weights[k] = 1.0 - (0.9 * k / (nlev - 1))

    for j in prange(1, nlat - 1):
        _zero_row(temp_3d, climo_3d, out_3d, j)

    # the two edge rows are read as neighbours but never computed on
    _zero_row(temp_3d, climo_3d, out_3d, 0)
    _zero_row(temp_3d, climo_3d, out_3d, nlat - 1)


@njit(fastmath=True, cache=True)
def _copy_row(io_buf, dst_3d, j):
    """dst_3d[:, j, :] = io_buf[:, j, :]  (float32 -> float64)"""
    nlev, nlat, nlon = dst_3d.shape
    for k in range(nlev):
        for i in range(nlon):
            dst_3d[k, j, i] = io_buf[k, j, i]


@njit(fastmath=True, cache=True)
def _add_row(io_buf, dst_3d, j, scale):
    """dst_3d[:, j, :] += scale * io_buf[:, j, :]  (float32 -> float64)"""
    nlev, nlat, nlon = dst_3d.shape
    for k in range(nlev):
        for i in range(nlon):
            dst_3d[k, j, i] += scale * io_buf[k, j, i]


@njit(parallel=True, fastmath=True, cache=True)
def accumulate_climo(io_buf, climo_3d, scale):
    """Pass 1: climo_3d += scale * io_buf, over the first-touch row bands."""
    nlat = climo_3d.shape[1]
    for j in prange(1, nlat - 1):
        _add_row(io_buf, climo_3d, j, scale)
    _add_row(io_buf, climo_3d, 0, scale)
    _add_row(io_buf, climo_3d, nlat - 1, scale)


@njit(parallel=True, fastmath=True, cache=True)
def ingest_and_compute_step(io_buf, temp_3d, climo_3d, out_3d, weights):
    """
    Pass 2, one time step:
      Step 1: copy the staging buffer into the NUMA-distributed temp_3d,
              each thread copying the row band it first-touched.
      Step 2: the fused kernel of calc_anomaly_numba.py --
              1. 3D anomaly from climo_3d, weighted by level
              2. centered vertical finite difference across levels
              3. 5-point horizontal regridding / smoothing stencil
    """
    nlev, nlat, nlon = temp_3d.shape
    w_center, w_ns, w_ew = 0.40, 0.15, 0.15

    # Step 1: parallel copy (the edge rows are only read as neighbours)
    for j in prange(1, nlat - 1):
        _copy_row(io_buf, temp_3d, j)
    _copy_row(io_buf, temp_3d, 0)
    _copy_row(io_buf, temp_3d, nlat - 1)

    # Step 2: fused anomaly + vertical difference + 5-point stencil
    for j in prange(1, nlat - 1):
        for k in range(1, nlev - 1):
            w_k = weights[k]
            for i in range(1, nlon - 1):
                anom = (temp_3d[k, j, i] - climo_3d[k, j, i]) * w_k
                vert_diff = 0.5 * (temp_3d[k + 1, j, i] - temp_3d[k - 1, j, i])
                horiz_regrid = (
                    w_center * temp_3d[k, j, i]
                    + w_ns * (temp_3d[k, j + 1, i] + temp_3d[k, j - 1, i])
                    + w_ew * (temp_3d[k, j, i + 1] + temp_3d[k, j, i - 1])
                ) - climo_3d[k, j, i]
                out_3d[k, j, i] = anom + vert_diff + horiz_regrid


# ---------------------------------------------------------------------------
# Helpers shared with calc_anomaly_numba_pario.py
# ---------------------------------------------------------------------------

def warm_up():
    """Compile the kernels (or load them from the cache) on tiny arrays."""
    dummy_3d = np.zeros((4, 8, 8), dtype=np.float64)
    dummy_buf = np.zeros((4, 8, 8), dtype=np.float32)
    dummy_w = np.empty(4, dtype=np.float64)
    parallel_first_touch_init(dummy_3d, dummy_3d, dummy_3d, dummy_w)
    accumulate_climo(dummy_buf, dummy_3d, 1.0)
    ingest_and_compute_step(dummy_buf, dummy_3d, dummy_3d, dummy_3d, dummy_w)


def allocate(shape_3d):
    """np.empty reserves address space only; first touch places the pages."""
    temp_3d = np.empty(shape_3d, dtype=np.float64)
    climo_3d = np.empty(shape_3d, dtype=np.float64)
    out_3d = np.empty(shape_3d, dtype=np.float64)
    weights = np.empty(shape_3d[0], dtype=np.float64)
    parallel_first_touch_init(temp_3d, climo_3d, out_3d, weights)
    return temp_3d, climo_3d, out_3d, weights


def arg_parser(description):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("--member", type=int, default=1, help="Step ID, for the output line")
    parser.add_argument("--file", default=ERA5_T_FILE, help="ERA5 NetCDF4 file")
    parser.add_argument("--var", default="T", help="4D variable (time, level, lat, lon)")
    parser.add_argument("--nsteps", type=int, default=0,
                        help="Use only the first NSTEPS time steps (0 = all)")
    return parser


def report(label, args, ntime, shape_3d, t_alloc, t_total, timers, checksum,
           array_nbytes, io_nbytes, extra=""):
    """One output line, the same layout for both scripts."""
    nlev, nlat, nlon = shape_3d
    # Uncompressed data delivered over both passes, and the minimum memory
    # traffic of the Numba part per time step, in array streams:
    #   pass 1: read io_buf, read + write climo_3d
    #   pass 2: copy   = read io_buf, write temp_3d (+ write-allocate)
    #           kernel = read temp_3d + climo_3d, write out_3d (+ write-allocate)
    gb_data = 2 * ntime * io_nbytes / 1e9
    gb_moved = ntime * ((io_nbytes + 2 * array_nbytes)
                        + (io_nbytes + 6 * array_nbytes)) / 1e9
    timer_txt = " | ".join(f"{k}: {v:.2f}s" for k, v in timers.items())
    print(
        f"[{label} {args.member:03d} | Host: {socket.gethostname()} | "
        f"Threads: {get_num_threads():2d}{extra}] "
        f"Steps: 2 x {ntime} x {nlev}x{nlat}x{nlon} | Alloc: {t_alloc:.2f}s | "
        f"{timer_txt} | Total: {t_total:.2f}s ({gb_data / t_total:4.2f} GB/s) | "
        f"Compute BW: {gb_moved / timers['Compute']:5.1f} GB/s | "
        f"Checksum: {checksum:.4f}"
    )


def main():
    args = arg_parser("Numba anomaly kernel on one ERA5 file, h5py read").parse_args()
    warm_up()

    # Open the NetCDF4 file directly with h5py: no netCDF4/xarray layer
    with h5py.File(args.file, "r") as f:
        var = f[args.var]                   # (time, level, latitude, longitude)
        shape_3d = var.shape[1:]
        ntime = var.shape[0] if args.nsteps <= 0 else min(args.nsteps, var.shape[0])

        t0 = time.perf_counter()
        temp_3d, climo_3d, out_3d, weights = allocate(shape_3d)
        io_buf = np.empty(shape_3d, dtype=var.dtype)   # reusable float32 staging buffer
        t_alloc = time.perf_counter() - t0

        t_read = 0.0    # read + decompress (HDF5, main thread only), both passes
        t_comp = 0.0    # Numba kernels, both passes
        checksum = 0.0
        t_start = time.perf_counter()

        # Pass 1: climo_3d = mean over the time steps
        for t in range(ntime):
            t0 = time.perf_counter()
            var.read_direct(io_buf, source_sel=np.s_[t])
            t1 = time.perf_counter()
            accumulate_climo(io_buf, climo_3d, 1.0 / ntime)
            t_read += t1 - t0
            t_comp += time.perf_counter() - t1

        # Pass 2: anomaly kernel on every time step
        for t in range(ntime):
            t0 = time.perf_counter()
            var.read_direct(io_buf, source_sel=np.s_[t])
            t1 = time.perf_counter()
            ingest_and_compute_step(io_buf, temp_3d, climo_3d, out_3d, weights)
            t_read += t1 - t0
            t_comp += time.perf_counter() - t1
            checksum += float(np.mean(out_3d[1:-1, ::60, ::60])) / ntime
        t_total = time.perf_counter() - t_start

    report("h5py", args, ntime, shape_3d, t_alloc, t_total,
           {"Read": t_read, "Compute": t_comp}, checksum,
           temp_3d.nbytes, io_buf.nbytes)


if __name__ == "__main__":
    main()
