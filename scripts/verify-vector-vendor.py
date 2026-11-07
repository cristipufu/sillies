#!/usr/bin/env python3
"""Verify the pinned native index snapshot without downloading or executing vendor code."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "Vendor" / "VectorSearch"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(arguments):
    expected = json.loads((ROOT / "SHA256SUMS.json").read_text())
    actual = {str(path.relative_to(ROOT)) for folder in ("faiss", "openmp")
              for path in (ROOT / folder).rglob("*") if path.is_file()}
    actual.update(("FAISS-LICENSE", "OPENMP-LICENSE", "upstream.json"))
    failures = []
    if actual != set(expected):
        failures.append("Vendored file inventory changed; review and regenerate SHA256SUMS.json.")
    for name, checksum in expected.items():
        path = ROOT / name
        if not path.is_file() or digest(path) != checksum:
            failures.append(f"Pinned content changed: {name}")
    for name in sorted(actual):
        original = None
        if name.startswith("faiss/") and arguments.faiss_source:
            original = arguments.faiss_source / name
        if name.startswith("openmp/") and arguments.openmp_source:
            relative = Path(name).relative_to("openmp")
            if relative.parts[0] not in ("generated", "public"):
                original = arguments.openmp_source / "runtime" / "src" / relative
        if original and (not original.is_file() or digest(original) != digest(ROOT / name)):
            failures.append(f"Upstream source mismatch: {name}")
    if (ROOT / "openmp/public/omp.h").read_bytes() != (ROOT / "openmp/generated/omp.h").read_bytes():
        failures.append("Public OpenMP header differs from the generated header.")
    if failures:
        raise SystemExit("\n".join(failures))
    print(f"Verified {len(expected)} pinned native vector files.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--faiss-source", type=Path, help="Optional checked-out Faiss root")
    parser.add_argument("--openmp-source", type=Path, help="Optional checked-out LLVM openmp/ root")
    verify(parser.parse_args())


if __name__ == "__main__":
    main()
