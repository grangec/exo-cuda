# tinygrad patches for exo-cuda

These patches fix CUDA memoryview read-only crashes when transferring
numpy arrays from NPY device to CUDA via `exec_copy` → `as_memoryview`.

## Cause

`NpyAllocator._as_buffer()` returns a read-only memoryview when the
underlying numpy array is read-only (e.g. from `np.frombuffer`).
`mv_address()` then crashes on `ctypes.c_char.from_buffer(mv)` because
it requires a writable buffer.

## Patches

| Patch | File | What |
|-------|------|------|
| `0001-*` | `tinygrad/runtime/ops_npy.py` | `_as_buffer`: `requirements='CW'` forces writable copy |
| `0002-*` | `tinygrad/helpers.py` | `mv_address`: fallback `.copy()` + debug log |

## Apply

```bash
cd .venv/lib/python3.12/site-packages/tinygrad/
patch -p2 < /path/to/exo-cuda/patches/0001-tinygrad-ops_npy-_as_buffer-writable.patch
patch -p2 < /path/to/exo-cuda/patches/0002-tinygrad-helpers-mv_address-readonly.patch
```

Or from exo-cuda root:

```bash
patch -p0 < patches/0001-tinygrad-ops_npy-_as_buffer-writable.patch
patch -p0 < patches/0002-tinygrad-helpers-mv_address-readonly.patch
```

## Revert

```bash
patch -p0 -R < patches/0001-tinygrad-ops_npy-_as_buffer-writable.patch
patch -p0 -R < patches/0002-tinygrad-helpers-mv_address-readonly.patch
```

## Apply after pip upgrade

After `pip install --upgrade tinygrad`, reapply both patches.
