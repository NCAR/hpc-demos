Yes — there are a few, and the one that best fits your constraints (8–16 threads, single node, shared-memory-sensitive, Python) is **dask's threaded scheduler driving an xarray reduction over gridded reanalysis or model output**. That's probably the single most common "threads packed into a node" pattern in earth system science today, and it's bandwidth-bound enough that NUMA placement shows up clearly.

## Why this one works for your demo

Dask's threaded scheduler runs a `ThreadPoolExecutor` in one process, so all chunks live in one address space. NumPy releases the GIL for array arithmetic and reductions, so you get real thread concurrency. Critically for you:

- **Work stealing breaks first-touch locality.** A chunk is allocated (first-touched) by whichever thread decoded or generated it, then the reduction task on that chunk may be scheduled onto a different thread. Without pinning, that's remote DRAM access on a near-random fraction of chunks. This is the part most people don't expect, and it means thread pinning alone isn't the whole fix — you'll want to contrast `--cpunodebind` with `--interleave=all` too.
- **Tree reductions share intermediates.** Partial sums produced by one thread get consumed by another in the next reduction level, so there's genuine inter-thread shared-memory traffic, not just embarrassingly parallel partitioning.
- **Low arithmetic intensity.** Means, anomalies, standard deviations, and percentiles are ~1 flop per word loaded, so you're measuring memory system behavior rather than FLOPs. (Avoid anything that lands in DGEMM — a compute-bound kernel will hide the NUMA difference entirely.)

A representative workload: daily climatology and anomaly from ERA5 or CESM history files.

```python
import os
os.environ["OMP_NUM_THREADS"] = "1"      # must be set before numpy import
import dask, dask.array as da

# ERA5-shaped: 0.25 deg global, ~8 GB float32
x = da.random.random((2000, 721, 1440), chunks=(50, 721, 1440)).astype("float32")

with dask.config.set(scheduler="threads", num_workers=16):
    anom = (x - x.mean(axis=0))
    result = anom.std(axis=0).compute()
```

Size the array so the working set is several times the aggregate L3 you're exposing — otherwise it stays resident and you measure nothing.

## A variant with explicit shared read-only state

If you want threads genuinely *sharing* a structure rather than partitioning one, use **regridding with precomputed ESMF weights**. Every thread reads the same sparse weight matrix while working on its own time slice. Sparse mat-vec is irregular and latency-bound, so remote-node access hurts more than it does for streaming reductions, and the shared matrix either sits in a shared L3 or gets replicated across caches depending on placement. `xesmf.Regridder` applied over a dask-chunked time dimension gets you this in about five lines, and regridding is as common as it gets in this field.

## Gotchas that will wreck the measurement

- **Thread oversubscription.** If dask runs 16 threads and each NumPy call fans out to 16 OpenBLAS/OpenMP threads, you get 256 threads and noise swamps everything. Set `OMP_NUM_THREADS=1`, `OPENBLAS_NUM_THREADS=1`, `MKL_NUM_THREADS=1` before import.
- **The HDF5 lock.** netCDF4-python serializes on a global HDF5 lock, which will serialize your reads and mask the threading behavior. Either load into memory first, or use Zarr (thread-safe, and blosc decompression releases the GIL — which is itself a nice bandwidth-heavy threaded kernel if you want a second data point).
- **Pure-Python work doesn't count.** Anything spending time in the interpreter won't scale at all under the GIL, so keep the hot loop inside NumPy or a `numba.njit(parallel=True, nogil=True)` kernel.

## On AMD EPYC specifically

If you're running this on Derecho-class hardware (dual EPYC Milan), the most dramatic effect isn't even cross-socket — it's **CCD scatter**. Milan has 8 cores per CCD with a private 32 MB L3 per CCD. Sixteen threads packed into 2 CCDs share two L3 slices; sixteen threads left to the scheduler can land on 8 different CCDs across both sockets, with eight disjoint L3s and no sharing benefit at all, plus Infinity Fabric hops for every miss. That contrast is visible without touching the memory controller story, and it makes a cleaner teaching narrative than socket-crossing alone.

## Running the comparison

```
# baseline: let the scheduler decide
python bench.py

# packed, local memory
numactl --cpunodebind=0 --membind=0 python bench.py

# pinned but memory spread
numactl --cpunodebind=0 --interleave=all python bench.py
```

For OpenMP codes, add `OMP_PLACES=cores` with `OMP_PROC_BIND=close` versus `spread` to show the CCD effect directly. Verify page placement with `numastat -p <pid>` and get remote-DRAM counters from `likwid-perfctr -g MEM_DP` or AMD uProf; `perf stat -e` works too if the uncore events are exposed on your nodes.

## If you'd rather use a compiled community code

`cdo -P 16` is the lowest-effort option and is genuinely ubiquitous — though note only some operators are OpenMP-threaded (remapping, ensemble statistics, detrend), so pick deliberately. WRF's OpenMP tiling and MPAS-A's threading are the "real model" options with true halo sharing between threads, but both are a much heavier lift to set up for a demo than they're worth unless you specifically need a dycore in the story.
