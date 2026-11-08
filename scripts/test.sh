#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
test_targets=()
configuration=debug
arguments=("$@")
for ((index=0; index<${#arguments[@]}; index++)); do
  case "${arguments[index]}" in
    --help|-h)
      python3 -B scripts/run-checked-tests.py --help
      exit 0
      ;;
    --bundle)
      index=$((index + 1))
      test_targets+=("${arguments[index]:-}")
      ;;
    --bundle=*) test_targets+=("${arguments[index]#--bundle=}") ;;
    --configuration)
      index=$((index + 1))
      configuration="${arguments[index]:-}"
      ;;
    --configuration=*) configuration="${arguments[index]#--configuration=}" ;;
  esac
done
case "$configuration" in
  debug|release) ;;
  *) echo "Unknown test configuration: $configuration" >&2; exit 2 ;;
esac
for target in ${test_targets[@]+"${test_targets[@]}"}; do
  if [[ ! "$target" =~ ^[[:alnum:]_]+Tests$ || ! -d "Tests/$target" ]]; then
    echo "Unknown test target: $target" >&2
    exit 2
  fi
done
build_arguments=(--configuration "$configuration")
if [[ "$configuration" == release ]]; then
  # Optimized @testable imports need a different compiler flag from the shipped app.
  # Keep this cache separate instead of invalidating release packaging on every test run.
  build_arguments+=(--scratch-path .build/performance -Xswiftc -enable-testing)
fi
build_started=$SECONDS
if (( ${#test_targets[@]} == 0 )); then
  swift build "${build_arguments[@]}" --build-tests
else
  for target in "${test_targets[@]}"; do
    swift build "${build_arguments[@]}" --target "$target"
  done
  if [[ " ${test_targets[*]} " == *" SilliesAppTests "* ]]; then
    swift build "${build_arguments[@]}" --product SilliesWindowMetadata
  fi
fi
echo "Test build ($configuration): $((SECONDS - build_started)) seconds."
test_binary_directory="$(swift build "${build_arguments[@]}" --show-bin-path)"
export SILLIES_METADATA_HELPER="$test_binary_directory/SilliesWindowMetadata"
# AppKit tests share NSApplication, WindowServer ordering, and the main run loop.
# Keep async fixtures from changing those globals underneath another fixture's measurements.
python3 -B scripts/run-checked-tests.py --bin-path "$test_binary_directory" "$@"
