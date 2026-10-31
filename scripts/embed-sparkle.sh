#!/bin/bash
# Embed the required updater runtime and make the app load its bundled copy.
set -euo pipefail

artifacts="${1:?Usage: embed-sparkle.sh artifacts-directory app-bundle}"
app="${2:?Usage: embed-sparkle.sh artifacts-directory app-bundle}"
if [[ ! -d "$artifacts" ]]; then
  echo "Cannot package Sillies: Sparkle artifacts are missing at $artifacts" >&2
  exit 1
fi
sparkle=$(find "$artifacts" -maxdepth 6 -path "*Sparkle.xcframework/macos-*/Sparkle.framework" -type d -print -quit)
if [[ -z "$sparkle" || ! -s "$sparkle/Versions/B/Sparkle" ]]; then
  echo "Cannot package Sillies: the required Sparkle framework is missing or incomplete." >&2
  exit 1
fi

executable="$app/Contents/MacOS/Sillies"
load_commands=$(otool -l "$executable")
framework="$app/Contents/Frameworks/Sparkle.framework"
mkdir -p "$app/Contents/Frameworks"
ditto "$sparkle" "$framework"
rm -rf "$framework/Versions/B/XPCServices" "$framework/XPCServices"

runtime_path='@executable_path/../Frameworks'
runtime_paths=$(printf '%s\n' "$load_commands" | awk '/cmd LC_RPATH/{getline; getline; print $2}')
if ! printf '%s\n' "$runtime_paths" | grep -Fxq "$runtime_path"; then
  install_name_tool -add_rpath "$runtime_path" "$executable"
fi
