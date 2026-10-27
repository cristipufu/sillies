#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
swift build --product SilliesWindowMetadata
export SILLIES_METADATA_HELPER="$(swift build --show-bin-path)/SilliesWindowMetadata"
# AppKit tests share NSApplication, WindowServer ordering, and the main run loop.
# Keep async fixtures from changing those globals underneath another fixture's measurements.
swift test --no-parallel "$@"
