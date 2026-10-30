#!/bin/bash
# Fast, synthetic resource and lifecycle checks. Device permissions/models are not required.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
swift build --build-tests
export SILLIES_METADATA_HELPER="$(swift build --show-bin-path)/SilliesWindowMetadata"
export SILLIES_LONG_AUDIO_CHECK=1
python3 scripts/run-bounded-test.py 90 swift test --skip-build --no-parallel --filter \
  'audioLifecycle|audioCaptureSequence|workspaceNotifications|workspaceFocusSequences|blockedUI|progressCoalescing|cancelledDelivery|repeatedAudioOverload|highChannelCountAudio|duplicateRecognizer|recognizerTimeout|cancellationRejects|partialRecognizer|sustainedAudioEncoding|trackingSchedule'
