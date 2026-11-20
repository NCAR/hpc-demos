#!/usr/bin/env python3
"""
make_climo_day.py MMDD
One calendar day of the long-term ERA5 temperature climatology.

Averages the 24 hourly fields of that calendar day over every year from
--first to --last (default 1991-2020, the WMO climate normal period; 29
February has only the leap years), and writes the mean as one 3D field,
float32 (level, latitude, longitude), to

    <--out>/T_<first>-<last>_MMDD.h5

uncompressed, so that calc_anomaly_numba_climo.py can read it quickly.
All 366 days together are 56 GB.  make_climo.sh runs the 366 days as
launch_cf steps.

Each year's file is read with calc_anomaly_numba_pario.py's parallel
decompression and added into a float64 sum over the same first-touch row
bands as the anomaly kernels.
"""
import argparse
import glob
import os
import time

# calc_anomaly_numba_io sets NUMBA_NUM_THREADS from OMP_NUM_THREADS on import
from calc_anomaly_numba_io import accumulate_climo, parallel_first_touch_init, warm_up
from calc_anomaly_numba_pario import chunk_locations, inflated_steps, unshuffle
import h5py
import numpy as np
from numba import get_num_threads

ROOT = "/glade/campaign/collections/gdex/data/d633000/e5.oper.an.pl"


def era5_file(year, mmdd):
    """The ERA5 temperature file of one day, or None if there isn't one (29 Feb)."""
    day = f"{year}{mmdd}"
    hits = glob.glob(f"{ROOT}/{day[:6]}/e5.oper.an.pl.128_130_t.ll025sc.{day}00_{day}23.nc")
    return hits[0] if hits else None


def main():
    parser = argparse.ArgumentParser(description="One calendar day of the ERA5 T climatology")
    parser.add_argument("mmdd", help="calendar day, e.g. 0101 or 0229")
    parser.add_argument("--first", type=int, default=1991, help="first year")
    parser.add_argument("--last", type=int, default=2020, help="last year")
    parser.add_argument("--out", default="climo", help="output directory")
    parser.add_argument("--var", default="T")
    args = parser.parse_args()

    files = [f for f in (era5_file(y, args.mmdd) for y in range(args.first, args.last + 1)) if f]
    if not files:
        raise SystemExit(f"no ERA5 files for {args.mmdd} in {args.first}-{args.last}")
    warm_up()

    with h5py.File(files[0], "r") as f:
        shape_3d = f[args.var].shape[1:]
        dtype = f[args.var].dtype
    nlev, nlat, nlon = shape_3d
    itemsize = dtype.itemsize
    nbytes = nlev * nlat * nlon * itemsize
    nio = get_num_threads()

    # float64 sum, first-touched (and zeroed) in parallel row bands
    total = np.empty(shape_3d, dtype=np.float64)
    parallel_first_touch_init(total, total, total, np.empty(nlev))
    io_buf = np.empty(shape_3d, dtype=dtype)
    io_u8 = io_buf.reshape(-1).view(np.uint8)

    t_wait = t_unsh = t_add = 0.0
    nfields = 0
    t_start = time.perf_counter()
    for path in files:
        with h5py.File(path, "r") as f:
            var = f[args.var]
            if var.shape[1:] != shape_3d:
                raise SystemExit(f"{path}: shape {var.shape} differs from {shape_3d}")
            locs = chunk_locations(var, var.shape[0])
        scale = 1.0 / (len(files) * len(locs))
        for t, raw, wait in inflated_steps(path, locs, nio, nbytes):
            t1 = time.perf_counter()
            unshuffle(np.frombuffer(raw, dtype=np.uint8), io_u8, nlev, nlat, nlon, itemsize)
            del raw
            t2 = time.perf_counter()
            accumulate_climo(io_buf, total, scale)
            t_wait += wait
            t_unsh += t2 - t1
            t_add += time.perf_counter() - t2
            nfields += 1
    t_read = time.perf_counter() - t_start

    os.makedirs(args.out, exist_ok=True)
    name = os.path.join(args.out, f"{args.var}_{args.first}-{args.last}_{args.mmdd}.h5")
    t0 = time.perf_counter()
    tmp = name + ".tmp"
    with h5py.File(tmp, "w") as f:      # written whole, then renamed: no half files
        d = f.create_dataset(args.var, data=total.astype(np.float32))
        d.attrs["description"] = (f"mean of the 24 hourly ERA5 {args.var} fields of calendar "
                                  f"day {args.mmdd} over the years listed")
        d.attrs["years"] = np.array([int(os.path.basename(p).split(".")[-2][:4]) for p in files])
        d.attrs["dims"] = "level, latitude, longitude (as in the ERA5 files)"
    os.replace(tmp, name)
    t_write = time.perf_counter() - t0

    print(f"[climo {args.mmdd} | Threads: {nio:2d}] Years: {len(files)} | Fields: {nfields} | "
          f"Wait: {t_wait:.2f}s | Unshuffle: {t_unsh:.2f}s | Add: {t_add:.2f}s | "
          f"Read total: {t_read:.2f}s | Write: {t_write:.2f}s | "
          f"Mean: {float(total[1:-1, ::60, ::60].mean()):.4f} K")


if __name__ == "__main__":
    main()
