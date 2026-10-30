#!/bin/bash
# Builds build/Sillies.app.
#
# Signs with $SILLIES_SIGNING_IDENTITY, else the first "Developer ID Application" identity in your keychain, else ad-hoc.
# A stable signature matters: macOS ties privacy grants (Accessibility, Screen & System Audio Recording) to it.
#
# Release builds (.github/workflows/release.yml) also set:
#   SILLIES_VERSION, SILLIES_BUILD_NUMBER  stamped into Info.plist (version like 1.2.3, build number digits)
#   SILLIES_FEED_URL                       stamped into SUFeedURL in Info.plist
#   SILLIES_KEYCHAIN                       the keychain holding the signing identity
#   SILLIES_TIMESTAMP=1                    a secure timestamp on the signature, which notarization requires
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh

configuration="${1:-release}"
case "$configuration" in debug|release) ;; *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;; esac

if [[ -n "${SILLIES_VERSION:-}" && ! "$SILLIES_VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "SILLIES_VERSION must look like 1.2.3" >&2; exit 1
fi
if [[ -n "${SILLIES_BUILD_NUMBER:-}" && ! "$SILLIES_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "SILLIES_BUILD_NUMBER must be digits" >&2; exit 1
fi

swift build --configuration "$configuration"
binary_dir="$(swift build --configuration "$configuration" --show-bin-path)"
app="$PWD/build/Sillies.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
install -m 755 "$binary_dir/Sillies" "$app/Contents/MacOS/Sillies"
mkdir -p "$app/Contents/Helpers"
install -m 755 "$binary_dir/SilliesWindowMetadata" "$app/Contents/Helpers/SilliesWindowMetadata"

sparkle=$(find .build/artifacts -path "*Sparkle.xcframework/macos-*/Sparkle.framework" -maxdepth 6 -type d 2>/dev/null | head -1)
if [[ -n "$sparkle" ]]; then
  mkdir -p "$app/Contents/Frameworks"
  ditto "$sparkle" "$app/Contents/Frameworks/Sparkle.framework"
  rm -rf "$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$app/Contents/Frameworks/Sparkle.framework/XPCServices"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$app/Contents/MacOS/Sillies" 2>/dev/null || true
fi

cp Info.plist "$app/Contents/Info.plist"
if [[ -n "${SILLIES_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SILLIES_VERSION" "$app/Contents/Info.plist"
fi
if [[ -n "${SILLIES_BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $SILLIES_BUILD_NUMBER" "$app/Contents/Info.plist"
fi
if [[ -n "${SILLIES_FEED_URL:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL $SILLIES_FEED_URL" "$app/Contents/Info.plist"
fi

rsync -a --delete Sources/SilliesApp/Resources/Characters/ "$app/Contents/Resources/Characters/"
rsync -a --delete Sources/SilliesApp/Resources/Scenes/ "$app/Contents/Resources/Scenes/"
ditto "$binary_dir/Sillies_SilliesModelStore.bundle" "$app/Contents/Resources/Sillies_SilliesModelStore.bundle"
mkdir -p "$app/Contents/Resources/ThirdPartyNotices"
cp .build/checkouts/argmax-oss-swift/LICENSE "$app/Contents/Resources/ThirdPartyNotices/ARGMAX-LICENSE"
cp .build/checkouts/argmax-oss-swift/NOTICES "$app/Contents/Resources/ThirdPartyNotices/ARGMAX-NOTICES"
cp .build/checkouts/FluidAudio/LICENSE "$app/Contents/Resources/ThirdPartyNotices/FLUIDAUDIO-LICENSE"
cp Vendor/AudioProcessing/WEBRTC-LICENSE Vendor/AudioProcessing/WEBRTC-PATENTS Vendor/AudioProcessing/ABSEIL-LICENSE "$app/Contents/Resources/ThirdPartyNotices/"
cp Vendor/AudioProcessing/webrtc/LICENSE "$app/Contents/Resources/ThirdPartyNotices/WEBRTC-AUTHORS-LICENSE"
cp Vendor/AudioProcessing/webrtc/third_party/pffft/LICENSE "$app/Contents/Resources/ThirdPartyNotices/PFFFT-LICENSE"
cp Vendor/AudioProcessing/webrtc/third_party/rnnoise/COPYING "$app/Contents/Resources/ThirdPartyNotices/RNNOISE-LICENSE"
cp Vendor/AudioProcessing/webrtc/common_audio/third_party/ooura/LICENSE "$app/Contents/Resources/ThirdPartyNotices/OOURA-LICENSE"
cp Vendor/AudioProcessing/webrtc/common_audio/third_party/spl_sqrt_floor/LICENSE "$app/Contents/Resources/ThirdPartyNotices/SPL-SQRT-LICENSE"
cp Vendor/AudioProcessing/webrtc/modules/third_party/fft/LICENSE "$app/Contents/Resources/ThirdPartyNotices/FFT-LICENSE"
swift scripts/make-icon.swift "$PWD/build"
cp build/Sillies.icns "$app/Contents/Resources/Sillies.icns"

identity="${SILLIES_SIGNING_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1 || true)
fi
sign=(--force --options runtime --sign "${identity:--}")
if [[ -n "${SILLIES_KEYCHAIN:-}" ]]; then sign+=(--keychain "$SILLIES_KEYCHAIN"); fi
if [[ "${SILLIES_TIMESTAMP:-}" == 1 && -n "$identity" ]]; then
  sign+=(--timestamp)
else
  sign+=(--timestamp=none)
fi

framework="$app/Contents/Frameworks/Sparkle.framework"
if [[ -d "$framework" ]]; then
  codesign "${sign[@]}" "$framework/Versions/B/Autoupdate" >/dev/null
  codesign "${sign[@]}" "$framework/Versions/B/Updater.app" >/dev/null
  codesign "${sign[@]}" "$framework" >/dev/null
fi
codesign "${sign[@]}" --identifier app.sillies.window-metadata "$app/Contents/Helpers/SilliesWindowMetadata" >/dev/null
codesign "${sign[@]}" --entitlements Sillies.entitlements --identifier app.sillies.macos "$app" >/dev/null

if [[ -n "$identity" ]]; then signer="Developer ID"; else signer="ad-hoc"; fi
printf 'Built %s (%s, signed %s)\n' "$app" "$configuration" "$signer"
