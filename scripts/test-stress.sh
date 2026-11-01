#!/bin/bash
# Fast, synthetic resource and lifecycle checks. Device permissions/models are not required.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
swift build --build-tests
export SILLIES_METADATA_HELPER="$(swift build --show-bin-path)/SilliesWindowMetadata"
export SILLIES_LONG_AUDIO_CHECK=1
python3 -B scripts/run-checked-tests.py --timeout 90 --bin-path "$(swift build --show-bin-path)" --filter \
  'SpeechWindowTests|SpeechSchedulerTests|WindowSpeechChannelTests|SpeechWorkerExecutorTests|StreamingDiarizationTests|SpeakerAttributionTests|speakerActivity|diarization|transcriptionFailurePreserves|audioLifecycle|audioCaptureSequence|workspaceNotifications|workspaceFocusSequences|blockedUI|progressCoalescing|cancelledDelivery|repeatedAudioOverload|highChannelCountAudio|duplicateRecognizer|recognizerTimeout|cancellationRejects|partialRecognizer|sustainedAudioEncoding|trackingSchedule|dictationRestart|dictationQuit|dictationFinalization|dictationLateInsertion|dictationUses|dictationHistoryFailure|writingHistory|vaultListing|isolatedDictation|isolatedSelection|fieldEdit|vaultProtection|vaultRegeneration|vaultScreenshotRetry|vaultShowMore|backgroundRefreshesStay|vaultMissingUpdate|incrementalNotes|quittingFlushesField|vaultCursor|vaultInvalidation|vaultWriteBurst|vaultRetry|failedVaultIndex|vaultStartup|largeVaultPages|oversizedVaultBodies|vaultDetail|vaultDeletion|failedRecordUpdate|backgroundOCR|thousandsOfPendingNotes|cancelledVaultNotes|speechRegistry|downloadedSpeechProviders|chat|voice|Voice|playback|Playback|cancellingStalledVoice'
