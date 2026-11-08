#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
swift build --build-tests
test_binary_directory="$(swift build --show-bin-path)"
export SILLIES_METADATA_HELPER="$test_binary_directory/SilliesWindowMetadata"
# AppKit tests share NSApplication, WindowServer ordering, and the main run loop.
# Keep async fixtures from changing those globals underneath another fixture's measurements.
if (( $# > 0 )); then
  python3 -B scripts/run-checked-tests.py --bin-path "$test_binary_directory" "$@"
else
  # Audio DSP, storage scale, and native workflows each get their own bounded run.
  # Every bundle belongs to exactly one batch, including future targets; all need receipts.
  for test_skip in \
    '^Sillies(Audio|Persistence|App)Tests([./]|$)' \
    '^(?!SilliesAudioTests([./]|$)).*' \
    '^(?!SilliesPersistenceTests([./]|$)).*' \
    '^(?!SilliesAppTests([./]|$)).*'; do
    python3 -B scripts/run-checked-tests.py --bin-path "$test_binary_directory" --skip "$test_skip"
  done
fi
