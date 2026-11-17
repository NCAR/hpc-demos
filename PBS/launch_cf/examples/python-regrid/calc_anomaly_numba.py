#!/usr/bin/env python3
"""
calc_anomaly_numba.py
Realistic memory-bound atmospheric post-processing & stencil regridding benchmark.
Uses Numba @njit(parallel=True) for both parallel First-Touch NUMA page allocation
and multi-threaded 5-point horizontal bilinear stencil remapping.

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

import numpy as np
from numba import njit, prange, get_num_threads


@njit(fastmath=True, cache=True)
def _init_row(temp_3d, climo_3d, out_3d, j, member_offset):
    """Fill latitude row j of every level."""
    nlev, nlat, nlon = temp_3d.shape
    for k in range(nlev):
        for i in range(nlon):
            temp_3d[k, j, i] = 288.15 + member_offset + 0.001 * (j + i)
            climo_3d[k, j, i] = 285.00 + 0.001 * (j + i)
            out_3d[k, j, i] = 0.0


@njit(parallel=True, fastmath=True, cache=True)
def parallel_first_touch_init(temp_3d, climo_3d, out_3d, weights, member_offset):
    """
    Faults virtual memory pages into physical RAM in parallel across threads.

    Linux puts a page in the NUMA domain of the thread that first writes it
    ("first touch").  The interior rows are split over the threads with the
    same prange(1, nlat - 1) as compute_atmospheric_kernels, so each thread
    first-touches the latitude band it will later compute on.  That keeps a
    band local only while its thread stays in the same domain, which is
    what numactl --cpunodebind guarantees and an unbound run does not.
    """
    nlev, nlat, nlon = temp_3d.shape

    for k in range(nlev):
        weights[k] = 1.0 - (0.9 * k / (nlev - 1))

    for j in prange(1, nlat - 1):
        _init_row(temp_3d, climo_3d, out_3d, j, member_offset)

    # the two edge rows are read as neighbours but never computed on
    _init_row(temp_3d, climo_3d, out_3d, 0, member_offset)
    _init_row(temp_3d, climo_3d, out_3d, nlat - 1, member_offset)


@njit(parallel=True, fastmath=True, cache=True)
def compute_atmospheric_kernels(temp_3d, climo_3d, out_3d, weights, iters):
    """
    Executes three memory-bandwidth-bound atmospheric post-processing kernels:
      1. 3D Climatological Anomaly weighted by pressure thickness
      2. Centered vertical finite difference (dT/dp proxy across levels)
      3. 5-point horizontal bilinear regridding / smoothing stencil
         (periodic in longitude, interior in latitude)
    Arithmetic intensity is < 0.25 FLOPs/Byte (purely memory-bandwidth bound).
    """
    nlev, nlat, nlon = temp_3d.shape

    # Realistic 5-point bilinear interpolation / smoothing weights (sum = 1.0)
    w_center = 0.40
    w_ns = 0.15  # North / South neighbors
    w_ew = 0.15  # East / West neighbors

    for it in range(iters):
        # Kernel 1 & 2: 3D Anomaly + Vertical Finite Difference + 5-Point Horizontal Stencil
        # Parallelized across (k, j) by parallelizing over latitude j (720 rows gives
        # fine-grained load balance across 4, 8, or 16 threads per task)
        for j in prange(1, nlat - 1):
            for k in range(1, nlev - 1):
                w_k = weights[k]
                for i in range(1, nlon - 1):
                    # 1. Climatological anomaly
                    anom = (temp_3d[k, j, i] - climo_3d[k, j, i]) * w_k

                    # 2. Vertical centered difference across pressure levels
                    vert_diff = 0.5 * (temp_3d[k + 1, j, i] - temp_3d[k - 1, j, i])

                    # 3. 5-point horizontal regridding stencil (sparse 2D operator)
                    horiz_regrid = (
                        w_center * temp_3d[k, j, i]
                        + w_ns * (temp_3d[k, j + 1, i] + temp_3d[k, j - 1, i])
                        + w_ew * (temp_3d[k, j, i + 1] + temp_3d[k, j, i - 1])
                    ) - climo_3d[k, j, i]

                    out_3d[k, j, i] = anom + vert_diff + horiz_regrid

        # Tiny update to prevent dead-code / loop-invariant optimization
        temp_3d[1, 1, 1] += 1e-9


def main():
    parser = argparse.ArgumentParser(description="Numba memory-bound atmospheric benchmark")
    parser.add_argument("--member", type=int, default=1, help="Ensemble member ID")
    parser.add_argument("--iters", type=int, default=40, help="Number of streaming iterations")
    parser.add_argument("--nlat", type=int, default=720, help="Latitude grid points")
    parser.add_argument("--nlon", type=int, default=1440, help="Longitude grid points")
    parser.add_argument("--nlev", type=int, default=32, help="Vertical pressure levels")
    args = parser.parse_args()

    # Warm up JIT compiler on tiny dummy arrays so compilation time isn't measured
    dummy_3d = np.empty((4, 8, 8), dtype=np.float64)
    dummy_w = np.empty(4, dtype=np.float64)
    parallel_first_touch_init(dummy_3d, dummy_3d, dummy_3d, dummy_w, 0.0)
    compute_atmospheric_kernels(dummy_3d, dummy_3d, dummy_3d, dummy_w, 1)

    t0_init = time.perf_counter()

    # Reserve virtual address space ONLY (np.empty does not touch physical RAM pages!)
    # Shape: (32, 720, 1440) float64 -> ~265.4 MB per 3D array (~796 MB total per task)
    shape_3d = (args.nlev, args.nlat, args.nlon)
    temp_3d = np.empty(shape_3d, dtype=np.float64)
    climo_3d = np.empty(shape_3d, dtype=np.float64)
    out_3d = np.empty(shape_3d, dtype=np.float64)
    weights = np.empty(args.nlev, dtype=np.float64)

    # Fault pages in parallel across active Numba threads (First-Touch NUMA allocation)
    parallel_first_touch_init(temp_3d, climo_3d, out_3d, weights, args.member * 0.01)
    t_alloc = time.perf_counter() - t0_init

    # Execute memory-bound stencil & regridding loop
    t0_comp = time.perf_counter()
    compute_atmospheric_kernels(temp_3d, climo_3d, out_3d, weights, args.iters)
    t_comp = time.perf_counter() - t0_comp

    # Minimum effective memory traffic per iteration:
    # Reads temp_3d + climo_3d (2x) and writes out_3d (1x + write-allocate read = 2x) -> ~4 array streams
    bytes_per_iter = 4 * temp_3d.nbytes
    gb_moved = (bytes_per_iter * args.iters) / 1e9
    eff_bw = gb_moved / t_comp

    host = socket.gethostname()
    active_threads = get_num_threads()
    checksum = float(np.mean(out_3d[1:-1, ::60, ::60]))

    print(
        f"[Member {args.member:03d} | Host: {host} | Threads: {active_threads:2d}] "
        f"Alloc: {t_alloc:.2f}s | Compute: {t_comp:.2f}s | "
        f"Est. BW: {eff_bw:5.1f} GB/s | Checksum: {checksum:.4f}"
    )


if __name__ == "__main__":
    main()