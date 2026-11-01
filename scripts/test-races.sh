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
# SwiftPM launches every target once per framework, including empty bundles. Run frameworks
# separately so startup overhead does not consume the other framework's test deadline.
# MLX explicitly does not support macOS TSAN (its CMakeLists.txt rejects that combination).
# GPU math runs in make check and real-helper checks; app/IPC/playback ownership stays instrumented.
race_filter='SpeechSchedulerTests|WindowSpeechChannelTests|SpeechWorkerExecutorTests|StreamingDiarizationTests|SpeakerAttributionTests|speakerActivity|diarization|speechRuntimeShares|transcriptionFailurePreserves|audioCaptureSequence|captureQueue|repeatedAudioOverload|highChannelCountAudio|duplicateRecognizer|recognizerTimeout|cancellationRejects|partialRecognizer|languageSwitch|finishingDuringLanguage|endingDuringSpeechPreparation|metadataProcess|metadataCacheSupportsConcurrent|blockedUI|progressCoalescing|cancelledDelivery|dictation|selection|Selection|writingHistory|writingRecovery|insertionRevalidates|nativeInsertion|clipboard|textAccessRejects|ocrSuspension|speechPreemptsText|cancelledText|missingModelsNever|suspendedText|workerExit|cancelledReasoning|cancellingAnUnresponsiveWorker|isolatedDictation|isolatedSelection|fieldEdit|vaultProtection|vaultRegeneration|vaultScreenshotRetry|vaultShowMore|backgroundRefreshesStay|vaultMissingUpdate|incrementalNotes|quittingFlushesField|vaultCursor|vaultInvalidation|vaultWriteBurst|vaultRetry|failedVaultIndex|vaultStartup|largeVaultPages|oversizedVaultBodies|vaultDetail|vaultDeletion|failedRecordUpdate|backgroundOCR|thousandsOfPendingNotes|cancelledVaultNotes|speechRegistry|downloadedSpeechProviders|languageRestart|voiceWarmup|chat|voice|Voice|playback|Playback|cancellingStalledVoice'
for race_framework in swift-testing xctest; do
  python3 -B scripts/run-checked-tests.py --sanitizer thread --timeout 90 --bin-path "$race_binary_directory" \
    --framework "$race_framework" --filter "$race_filter" --skip 'SilliesFishSpeechTests'
done
