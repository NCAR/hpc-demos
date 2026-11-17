# Adding IO to the regrid example to see how that changes the trends

My prompt: "What is the fastest method for reading one of the ERAS files and processing it in a script like `calc_anamoly_numba.py`? Or would that not make sense because you'd typically regrid the other file to compare with ERAS data?"

## Answer

Your scientific intuition is spot on: **in standard diagnostic workflows, ERA5 (`d633000` on `/glade/campaign/collections/rda`) is the canonical reference target**, meaning you normally regrid your model ensemble output *onto* the ERA5 grid to compute biases or anomalies against it.

However, there are also major NCAR workflows where you **do** regrid ERA5 itself—most notably when generating **initial/boundary conditions (IC/BCs)** to nudge or force a model (interpolating ERA5 onto an unstructured MPAS mesh, a CAM-SE spectral element grid, or a regional WRF domain), or when coarsening ERA5 to match a $1^\circ$ CESM ensemble (`f09_g17`).

Regardless of whether ERA5 is the source being regridded or the target reference `climo_3d` being subtracted, if you want to feed real ERA5 files from `/glade` into `calc_anomaly_numba.py` at maximum speed, here is how to bypass Python I/O bottlenecks and preserve your `numactl` First-Touch locality.

---

### 1. The Fastest Way to Read ERA5 NetCDF4 Files in Python

On NCAR's `/glade/campaign` (and `/glade/derecho/scratch`), ERA5 pressure-level files are stored as **HDF5-backed NetCDF4 files**—often with internal **chunking** and **DEFLATE (zlib) compression** (or `scale_factor`/`add_offset` packing).

If you use high-level `xarray.open_dataset()`, `xarray` adds metadata parsing overhead, constructs coordinate indexes, and—most dangerously for your `numactl` tutorial—**allocates a brand-new NumPy array on the main thread every time you slice a time step** (`ds['T'].isel(time=t).values`), destroying your parallel First-Touch NUMA page placement.

#### Speed Hierarchy for Reading ERA5 into Numba

| Method | Relative Speed | Preserves `numactl` First-Touch? | Why / When to Use |
| --- | --- | --- | --- |
| **1. `h5py` with `.read_direct()**` | **Fastest (1.0x baseline)** | **Yes (via parallel copy)** | Bypasses the C `libnetcdf` wrapper entirely and reads HDF5 chunks directly into a pre-allocated buffer without creating temporary arrays. |
| **2. `netCDF4` (C-API wrapper)** | **Very Fast (~1.05x–1.15x)** | **Partially** | Calling `nc.variables['T'][t, :, :, :]` is fast and handles `scale_factor` unpacking in C, but allocates a new array on the master thread each slice. |
| **3. Zarr / Uncompressed Binary (`np.memmap`)** | **Hardware Limit** | **Yes** | If ERA5 data has been converted to uncompressed Zarr (e.g., ARCO-ERA5) or raw binary on scratch, threads can read chunks in parallel. |
| **4. `xarray.open_dataset()**` | **Slowest (~1.5x–3x slower)** | **No** | Great for interactive analysis, but constructs lazy wrappers, coordinate indices, and single-threaded heap allocations on every `.values` call. |

---

### 2. The Crucial Caveat: HDF5 Decompression is Single-Threaded!

When reading compressed ERA5 NetCDF4 files from `/glade/campaign/collections/rda/data/d633000/`, the bottleneck is rarely Lustre disk bandwidth—it is **CPU-bound single-threaded `zlib` decompression** inside the HDF5 C library:

* The standard HDF5 library is **not thread-safe** and decompresses chunks on a **single core** (Core 0 of your task).
* Because `launch_cf` packs **16 to 32 independent processes** onto a Derecho node, **process-level parallelism (`launch_cf`) completely overcomes single-threaded HDF5 decompression!** All 32 processes decompress their own ERA5/model files simultaneously across 32 separate cores.

#### How to Keep First-Touch NUMA Locality When Reading Files

Because `h5py` or `netCDF4` reads data on the single master thread of each Python process, if you read directly into `temp_3d`, all 265 MB of physical RAM pages will fault onto the master thread's core/NUMA domain.

To keep your **`@njit(parallel=True)` First-Touch NUMA distribution**, use a **single-slice staging buffer (`io_buf`)** and copy/cast it into your parallel-faulted `temp_3d` inside the Numba `prange` loop:

```python
import h5py
import numpy as np
from numba import njit, prange

@njit(parallel=True, fastmath=True)
def ingest_and_compute_step(io_buf, temp_3d, climo_3d, out_3d, weights):
    """
    Copies the newly read 3D slice from the I/O staging buffer into the
    parallel First-Touched temp_3d array (distributed across NUMA/L3 caches)
    and immediately runs the fused anomaly + vertical + horizontal stencil.
    """
    nlev, nlat, nlon = temp_3d.shape
    w_center, w_ns, w_ew = 0.40, 0.15, 0.15

    # Step 1: Parallel copy from staging buffer into NUMA-distributed temp_3d
    for j in prange(nlat):
        for k in range(nlev):
            for i in range(nlon):
                temp_3d[k, j, i] = io_buf[k, j, i]

    # Step 2: Fused Anomaly + Vertical Diff + 5-Point Horizontal Stencil
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

```

And in your main time loop, use `h5py`'s zero-allocation **`read_direct`** into the reusable `io_buf`:

```python
# Allocate a reusable 3D staging buffer once (float32 matches ERA5 storage on disk)
io_buf = np.empty((nlev, nlat, nlon), dtype=np.float32)

# Open the NetCDF4 file directly with h5py (fastest path, zero netCDF4 overhead)
with h5py.File(era5_or_model_filepath, "r") as f:
    t_var = f["T"]  # Shape on disk: (time, level, latitude, longitude)
    ntime = t_var.shape[0]

    for t in range(ntime):
        # Zero-allocation direct read of time slice 't' into pre-allocated io_buf
        t_var.read_direct(io_buf, source_sel=np.s_[t, :nlev, :nlat, :nlon])
        
        # Parallel ingest + compute across pinned Numba threads
        ingest_and_compute_step(io_buf, temp_3d, climo_3d, out_3d, weights)

```

---

### 3. How to Frame This in Your Tutorial (Synthetic vs. Real `/glade` I/O)

If an attendee asks why the tutorial uses synthetic arrays in RAM instead of reading directly from `/glade/campaign/collections/rda/data/d633000` (ERA5), you can point out two practical lessons:

1. **Separating Scientific Role from Benchmark Role:**
In a real workflow, each `launch_cf` task would read **one ERA5 climatology file once** into `climo_3d` (which is already on the $721 \times 1440$ target grid), and then loop over time slices of **an ensemble member's model output file** into `temp_3d`, regridding `temp_3d` onto the ERA5 grid and subtracting `climo_3d`.
2. **Why `h5py.read_direct()` + Pre-Allocated Buffers Beat `xarray` Inside Loops:**
When users write naive `xarray` loops over time slices, Python spends half its time calling `mmap`/`munmap` to allocate and garbage-collect temporary arrays on the master thread, which breaks NUMA locality. Pre-allocating `temp_3d`, `climo_3d`, and `out_3d` with `np.empty()` (faulted via Numba `prange`) and streaming time slices through a reusable `read_direct` staging buffer gives them both **maximum I/O speed** and **strict NUMA memory locality**.