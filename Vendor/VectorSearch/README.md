# Native vector search

This package builds a CPU-only vector index from pinned **Meta Faiss** and **LLVM OpenMP** sources.
Only `SilliesSearchInference` loads the Swift adapter and this package. The main app, Core,
Persistence and Vault targets do not link the native index. Apple Accelerate supplies BLAS.
No Python environment, Homebrew library, network service or runtime download is required.

| Component | Version / source | License |
| --- | --- | --- |
| Faiss | [v1.15.1](https://github.com/facebookresearch/faiss/tree/v1.15.1) | [MIT](FAISS-LICENSE) |
| LLVM OpenMP | [llvmorg-21.1.4](https://github.com/llvm/llvm-project/tree/llvmorg-21.1.4/openmp) | [Apache-2.0 with LLVM exceptions](OPENMP-LICENSE) |

Exact revisions and build configuration are in [upstream.json](upstream.json). Upstream source files
are unchanged. `VectorSearch.cpp` is Sillies' small checked C interface; it bounds dimensions,
batches and worker count and converts native exceptions into recoverable failures.

## Integration

- Apple silicon, macOS 26 or later, C++20, static OpenMP, no GPU/Python/Metal extension.
- Exact inner-product search is used for small indexes. Larger indexes use an on-disk IVF scalar
  quantizer. Query-time work never trains an index. See the [Vault guide](../../docs/contributing/vault.md).
- OpenMP uses two workers; on-disk prefetch uses one. Accelerate may manage its own BLAS workers.
- IVF queries probe up to 96 partitions and return at most 256 candidates. The
  [retrieval qualification](../../docs/reports/vault-qualification-2026-11-07.md) compares this policy
  with 24 and 64 probes using real embeddings and a separate million-vector latency check.
- `-g0` on the OpenMP target avoids an Xcode 27 debug-note linker failure observed with the static
  upstream runtime. It does not disable Swift diagnostics or change the runtime's source.
- Native stdout is redirected to stderr inside the search helper before loading Faiss. Diagnostic
  messages cannot enter the framed inference protocol.

## Updating the vendor snapshot

1. Check out the exact Faiss and LLVM tags/revisions. Keep their licenses and provenance together.
2. Configure the official CPU-only Faiss CMake target with GPU, Metal, Python, tests and extras off,
   MKL off, and Accelerate BLAS. Use the generic ARM/NEON source list from that target, including
   `OnDiskInvertedLists.cpp`. Copy the needed `faiss/` headers and sources without editing them.
3. Configure LLVM's `openmp/` with `CMAKE_BUILD_TYPE=Release`, `CMAKE_OSX_DEPLOYMENT_TARGET=26.0`,
   `LIBOMP_ARCH=aarch64`, `LIBOMP_ENABLE_SHARED=OFF`, `LIBOMP_OMPT_SUPPORT=OFF` and
   `LIBOMP_USE_HWLOC=OFF`. Copy runtime sources, i18n headers and generated `kmp_config.h`,
   `kmp_i18n_id.inc`, `kmp_i18n_default.inc` and `omp.h` into the corresponding local directories.
   Generated headers are committed so a normal Sillies build does not need CMake.
4. Reconcile explicit source lists and compiler definitions in `Package.swift` against the official
   CMake output. Do not add host-specific include paths or dynamic Homebrew dependencies.
5. Run `scripts/verify-vector-vendor.py` with the two source checkouts. Regenerate notices with
   `scripts/third-party-notices.py`, then run `make check`. Test checkpoint restart, deletion,
   interrupted writes, provider replacement and the on-disk index, not only exact search.

The generated configuration is for this supported platform. Adding another architecture requires
regenerating and qualifying its configuration; copying the ARM definitions is insufficient.
