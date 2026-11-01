#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
swift build --build-tests
export SILLIES_METADATA_HELPER="$(swift build --show-bin-path)/SilliesWindowMetadata"
# AppKit tests share NSApplication, WindowServer ordering, and the main run loop.
# Keep async fixtures from changing those globals underneath another fixture's measurements.
python3 -B scripts/run-checked-tests.py --bin-path "$(swift build --show-bin-path)" "$@"
