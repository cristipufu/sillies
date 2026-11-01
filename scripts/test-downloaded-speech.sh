#!/bin/bash
# Opt-in real ASR + native interaction check. Uses generated audio, never a device.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
if [[ $# != 2 ]]; then
  echo "Usage: $0 MODEL_ID MODEL_STORE_DIRECTORY" >&2
  exit 2
fi
export SILLIES_STT_MODEL="$1" SILLIES_STT_STORE="$2"
swift build --build-tests
export SILLIES_METADATA_HELPER="$(swift build --show-bin-path)/SilliesWindowMetadata"
fixture_directory=$(mktemp -d)
trap 'rm -rf "$fixture_directory"' EXIT
export SILLIES_SPEECH_FIXTURE="$fixture_directory/meeting.aiff"
say -v Samantha -r 155 -o "$SILLIES_SPEECH_FIXTURE" \
  'We agreed to ship the report on Friday. Alex will review the draft tomorrow. The owner of the customer follow-up is still undecided.'
# Cold Core ML specialization is separate from the short execution budget.
SILLIES_STT_PREPARE_ONLY=1 python3 -B scripts/run-checked-tests.py --timeout 300 --bin-path "$(swift build --show-bin-path)" \
  --filter prepareDownloadedSpeechModelForIntegration
SILLIES_DOWNLOADED_STT_CHECK=1 python3 -B scripts/run-checked-tests.py --timeout 90 --bin-path "$(swift build --show-bin-path)" \
  --filter downloadedSpeechModelsKeepAllInteractionPathsWithinBudget
