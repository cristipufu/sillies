#!/bin/bash
# Parse Swift syntax using the selected toolchain; no external checker dependency is downloaded.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
compiler=$(xcrun --find swiftc)
syntax_lib="$(dirname "$compiler")/../lib/swift/host"
checker_dir=.build/architecture-check
mkdir -p "$checker_dir"
# Always compile the small checker so toolchain upgrades cannot reuse an incompatible binary.
"$compiler" -sdk "$(xcrun --show-sdk-path)" -I "$syntax_lib" -L "$syntax_lib" \
  -Xlinker -rpath -Xlinker "$syntax_lib" \
  Tools/ArchitectureCheck/*.swift -o "$checker_dir/check"
"$checker_dir/check"
