#!/bin/bash
# Instrument lifecycle/concurrency checks without changing normal performance-test builds.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh

race_build_directory=".build/thread-sanitizer"
swift build --scratch-path "$race_build_directory" --sanitize thread --build-tests
race_binary_directory="$(swift build --scratch-path "$race_build_directory" --show-bin-path)"
export SILLIES_METADATA_HELPER="$race_binary_directory/SilliesWindowMetadata"
# A reported race must fail the command. Do not suppress reports from application code.
export TSAN_OPTIONS="halt_on_error=1:exitcode=66"
python3 scripts/run-bounded-test.py 90 swift test \
  --scratch-path "$race_build_directory" --sanitize thread --skip-build --no-parallel --filter \
  'SpeechSchedulerTests|WindowSpeechChannelTests|SpeechWorkerExecutorTests|StreamingDiarizationTests|SpeakerAttributionTests|speakerActivity|diarization|speechRuntimeShares|transcriptionFailurePreserves|audioCaptureSequence|captureQueue|repeatedAudioOverload|highChannelCountAudio|duplicateRecognizer|recognizerTimeout|cancellationRejects|partialRecognizer|languageSwitch|finishingDuringLanguage|endingDuringSpeechPreparation|metadataProcess|metadataCacheSupportsConcurrent|blockedUI|progressCoalescing|cancelledDelivery|dictation|selection|Selection|writingHistory|writingRecovery|insertionRevalidates|nativeInsertion|clipboard|textAccessRejects|ocrSuspension|speechPreemptsText|cancelledText|missingModelsNever|suspendedText|workerExit|cancelledReasoning|cancellingAnUnresponsiveWorker|isolatedDictation|isolatedSelection|fieldEdit|vaultProtection|vaultRegeneration|vaultScreenshotRetry|vaultShowMore|backgroundRefreshesStay|vaultMissingUpdate|incrementalNotes|quittingFlushesField|vaultCursor|vaultInvalidation|vaultWriteBurst|vaultRetry|failedVaultIndex|vaultStartup|largeVaultPages|oversizedVaultBodies|vaultDetail|vaultDeletion|failedRecordUpdate|backgroundOCR|thousandsOfPendingNotes|cancelledVaultNotes|speechRegistry|downloadedSpeechProviders'
