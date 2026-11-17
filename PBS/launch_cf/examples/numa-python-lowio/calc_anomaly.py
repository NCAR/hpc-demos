#!/usr/bin/env python3
"""
calc_anomaly.py
Synthetic memory-bound atmospheric post-processing benchmark for NCAR Derecho.
Combines multi-threaded OpenBLAS matrix multiplication (spectral/grid transform)
and high-bandwidth 3D array streaming (anomaly + vertical difference).
"""
import argparse
import os
import time
import socket
import numpy as np
import random

def main():
    parser = argparse.ArgumentParser(description="Memory-bound atmospheric benchmark")
    parser.add_argument("--member", type=int, default=1, help="Ensemble member ID")
    parser.add_argument("--iters", type=int, default=25, help="Number of streaming iterations")
    parser.add_argument("--nlat", type=int, default=720, help="Latitude grid points")
    parser.add_argument("--nlon", type=int, default=1440, help="Longitude grid points")
    parser.add_argument("--nlev", type=int, default=32, help="Vertical pressure levels")
    args = parser.parse_args()

    t0_init = time.perf_counter()

    # Shape: (nlev, nlat, nlon) -> 32 * 720 * 1440 * 8 bytes ~= 265 MB per 3D field
    shape_3d = (args.nlev, args.nlat, args.nlon)
    
    # Allocate and immediately touch every page in memory ("First-Touch" allocation)
    # Total footprint per task is ~1.1 GB
    temp_3d = np.full(shape_3d, 288.15 + (args.member * 0.01), dtype=np.float64)
    climo_3d = np.full(shape_3d, 285.00, dtype=np.float64)
    pressure_weights = np.linspace(1.0, 0.1, args.nlev, dtype=np.float64)[:, None, None]
    out_3d = np.zeros(shape_3d, dtype=np.float64)

    # 2D spectral/regridding weight matrix to exercise OpenBLAS threads via np.dot
    # (nlat, nlat) x (nlat, nlon) per level
    regrid_op = np.eye(args.nlat, dtype=np.float64) * 0.999

    t_alloc = time.perf_counter() - t0_init

    # Main memory-bound compute loop
    t0_comp = time.perf_counter()
    for it in range(args.iters):
        # 1. Stream 3D arrays: Anomaly calculation + vertical weighting (Memory Bandwidth bound)
        out_3d[:] = (temp_3d - climo_3d) * pressure_weights

        # 2. Vertical finite difference across pressure levels (Cache-thrashing stride)
        out_3d[1:-1, :, :] += 0.5 * (temp_3d[2:, :, :] - temp_3d[:-2, :, :])

        # 3. Multi-threaded BLAS operation across levels (Exercises OPENBLAS_NUM_THREADS)
        for k in range(0, args.nlev, 4):
            out_3d[k] = np.dot(regrid_op, out_3d[k])

        # Slight perturbation to prevent compiler/interpreter loop hoisting
        temp_3d[0, 0, 0] += 1e-9*random.random()

    t_comp = time.perf_counter() - t0_comp

    # Approximate bytes moved in the streaming steps per iteration:
    # Step 1 reads temp_3d, climo_3d, writes out_3d (~3 * 265 MB)
    # Step 2 reads 2 slices of temp_3d, reads/writes out_3d (~4 * 265 MB)
    bytes_per_iter = 7 * temp_3d.nbytes
    gb_Moved = (bytes_per_iter * args.iters) / 1e9
    eff_bw = gb_Moved / t_comp

    host = socket.gethostname()
    omp_threads = os.environ.get("OMP_NUM_THREADS", "unset")
    checksum = float(np.mean(out_3d[:, ::60, ::60]))

    print(
        f"[Member {args.member:03d} | Host: {host} | Threads: {omp_threads}] "
        f"Alloc: {t_alloc:.2f}s | Compute: {t_comp:.2f}s | "
        f"Est. Stream BW: {eff_bw:.1f} GB/s | Checksum: {checksum:.4f}"
    )

if __name__ == "__main__":
    main()
