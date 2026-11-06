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
audio_echo_filter='voiceConversationRejectsEchoAcrossAcousticDelays|voiceConversationStillAcceptsRealSpeechDuringPlayback'
audio_timing_filter='voiceConversationResamplesDeviceQuantaWithoutSelfInterruption|meetingResampling'
audio_signal_filter="$audio_echo_filter|$audio_timing_filter"
# The device/rate matrix processes many seconds of PCM under instrumentation. Give it its own
# bounded run, separate from acoustic-delay and lifecycle checks; keep every case instrumented.
race_filter='SpeechSchedulerTests|WindowSpeechChannelTests|SpeechWorkerExecutorTests|StreamingDiarizationTests|SpeakerAttributionTests|speakerActivity|diarization|speechRuntimeShares|transcriptionFailurePreserves|audioCaptureSequence|captureQueue|repeatedAudioOverload|highChannelCountAudio|duplicateRecognizer|recognizerTimeout|cancellationRejects|partialRecognizer|languageSwitch|finishingDuringLanguage|endingDuringSpeechPreparation|metadataProcess|metadataCacheSupportsConcurrent|blockedUI|progressCoalescing|cancelledDelivery|dictation|selection|Selection|writingHistory|writingRecovery|insertionRevalidates|nativeInsertion|clipboard|textAccessRejects|ocrSuspension|speechPreemptsText|cancelledText|missingModelsNever|suspendedText|workerExit|cancelledReasoning|cancellingAnUnresponsiveWorker|isolatedDictation|isolatedSelection|fieldEdit|vaultProtection|vaultRegeneration|vaultScreenshotRetry|vaultShowMore|backgroundRefreshesStay|vaultMissingUpdate|incrementalNotes|quittingFlushesField|vaultCursor|vaultInvalidation|vaultWriteBurst|vaultRetry|failedVaultIndex|vaultStartup|largeVaultPages|oversizedVaultBodies|vaultDetail|vaultDeletion|failedRecordUpdate|backgroundOCR|thousandsOfPendingNotes|cancelledVaultNotes|speechRegistry|downloadedSpeechProviders|languageRestart|voiceWarmup|chat|ChatPresentation|TextPresentation|voice|Voice|playback|Playback|cancellingStalledVoice|sameTurnText|oversizedVoice|cancelledVoiceAdmission|cachedModels|speechTextStream|SpeechConsumer|speechQueue|SpeechStream|preemptedTextStream|textWorkerStream|textWorkerRejects|interruptingAStream|modelFailureAfterPartial|streamedVoice|spokenPhraseCompletion'
voice_bundles='Chat|TTS|TextModels|VoicePlayback|Writing'
race_filter="$race_filter|explicitMemory|reviewedMemory|explicitCorrection|automaticMemoryWritesCannot|emptyInterruption|realWordsCancel|audioOnlyPreemption|closingDuringRecovered|InteractiveSpeechChannelTests|diagnostics|sharedIndexAdmission|sharedEmbedding|semanticDeadline|stoppingMemoryIndex|replacingEmbeddingProvider|vaultSemantic|closingTheBoundMeeting|metadataExactLookup|setup|Setup|directChat|directTalk|microphoneTrial|companionBackend|companionProfile|conversationAdmission|conversationIdeas|pendingQuestion|conversationSearchRejects|conversationReading|conversationUsability|clarificationEnds|clarificationPersistence|appleClarification|nativeClarification|malformedClarification|conversationDate|conversationExport|cancelledConversationExport|clearingHistoryDuringExport|talkClarification"
# Each bundle belongs to exactly one batch, including future targets in the first batch.
# TSAN process startup/discovery is substantial; keep the existing per-run watchdog bounded.
for race_skip in \
  "Sillies($voice_bundles)Tests|SilliesFishSpeechTests|$audio_signal_filter" \
  "Sillies(?!($voice_bundles)Tests).*"; do
  python3 -B scripts/run-checked-tests.py --sanitizer thread --timeout 90 --bin-path "$race_binary_directory" \
    --framework swift-testing --filter "$race_filter" --skip "$race_skip"
done
python3 -B scripts/run-checked-tests.py --sanitizer thread --timeout 90 --bin-path "$race_binary_directory" \
  --framework xctest --filter "$race_filter" --skip "SilliesFishSpeechTests|$audio_signal_filter"
for race_audio_filter in "$audio_timing_filter" "$audio_echo_filter"; do
  python3 -B scripts/run-checked-tests.py --sanitizer thread --timeout 90 --bin-path "$race_binary_directory" \
    --framework swift-testing --filter "$race_audio_filter" --skip 'Sillies(?!AudioTests).*'
done
