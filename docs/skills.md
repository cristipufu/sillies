# Companion skills

The wheel and the mascot's context menu expose the same five actions. Hover over a target window while dragging to reveal the wheel, move to a bubble, then release. Without a choice, the mascot returns quietly and preserves any running skill. Record is also in the menu bar and needs no selected window.

| Skill | Input | Result |
| --- | --- | --- |
| Listen | Selected application’s output and microphone | Playable recording, local transcript, summary and explicit action items |
| Participate | The same audio as Listen | The same recording and notes, plus one live suggestion in a mascot speech bubble |
| Snap | One selected window image | PNG on clipboard and in the Vault immediately; background OCR adds searchable text |
| Explain | One selected window image | PNG, Vision OCR, summary and plain-language explanation of the recognized text |
| Record | Built-in microphone where available; otherwise default microphone | Playable `.m4a` AAC file, local transcript, summary and action items |

ScreenCaptureKit's audio filter is application-wide. Selecting a Google Meet browser window includes audio playing in other tabs of that browser. Sillies does not claim per-tab isolation. Microphone speech is labeled separately from app speech. Optional downloaded speaker detection adds source-scoped speaker numbers. Users can name speakers per saved recording; names update transcript headers and regenerated notes without changing spoken words. Source labels alone do not identify individual people. Both meeting skills apply local acoustic echo cancellation to support laptop speakers. Explain reasons over OCR text, not invisible content or the visual meaning of images alone.

## Capture and meeting apps

ApplicationAudioSource only subscribes to ScreenCaptureKit audio. MicrophoneAudioSource uses an independent AVCaptureSession, prefers a device with built-in transport, and never locks a device for configuration. There are no system-device, format, volume, mute, routing, virtual-driver, meeting-UI, or voice-processing changes. The app has the hardened-runtime audio-input entitlement; macOS permissions are still required. Capture is never started on launch or by hovering.

Listen and Participate require both inputs to start successfully. A failed or interrupted input produces an explicit stopped state, stops the capture producers, and lets the user save the partial transcript. It does not silently continue as a complete meeting recording. One audio session is allowed across the crew, including while it is finishing.

Muting Meet or Zoom does not mute Sillies’ independent microphone. Both meeting skills record and transcribe the app output plus an echo-reduced microphone stream; only Participate generates suggestions. All three audio skills save playable AAC recordings. Headphones are optional. Cancellation reduces speaker echo, but clipping, unusual device routing, and room acoustics can still affect recognition.

All audio modes share preparing, capturing, paused, finishing, failed, and finished presentation. Pause discards incoming audio without saving/transcribing it, while keeping input access ready for Resume. Finish stops sources, drains transcription, closes the AAC container, then writes the Vault record. There is a bounded eight-second speech-finalization deadline; a timeout preserves available text and reports the limitation. Audio skills start with the transcription window closed. Open it explicitly from the mascot bar, context menu, or control center; closing it keeps capture running. This utility window accepts typing and language selection but is excluded from companion attachment and skill drop targets, including native focus/move/resize notifications. Pausing the app, an exclusion, removing the companion, and termination all stop the session and retain partial work.

Termination completions use MainRunLoopDelivery (common and modal-panel modes). Capture finalization does not rely on the main actor task executor being drained by AppKit's termination modal loop.

Bound mascots order immediately above the target window. Their bars and suggestion bubbles sit above peer mascots in the same native window layer, so walking companions cannot cover the text. Normal-window overlays remain below floating application windows; floating-window overlays use the corresponding higher level. They hide when the target window is offscreen, minimized, or completely covered, retaining their binding and attachment slot while capture continues. The existing skill refresh reads one bounded window-metadata stack on a worker; coverage is rectangular metadata, not pixel inspection. The transcription utility window appears above mascots and bars and remains excluded as an attachment target.

## Local processing

Sillies requires macOS 26 or later. SpeechAnalyzer/SpeechTranscriber handles long-running speech, using two independent channels for both meeting skills. The Spoken language menu lists system-supported locales and distinguishes models already installed on this Mac from unavailable ones. Sillies never requests a model download. Recognition requires an explicit locale; it does not infer the spoken language from audio. No remote recognition fallback is enabled. SpeechAnalyzer does not require the older Speech Recognition authorization; microphone and system-audio permissions still apply.

The remembered installed language is used at startup; otherwise Sillies chooses an installed match for the device language. If neither is available, the mascot bar asks the user to open the transcript and choose a ready language. Changes affect new speech, preserve earlier text, and switch both meeting channels together. Audio capture and the recording file remain open while recognizers change; bounded buffering bridges the switch. A paused session remains paused. The final selection is saved with the record and controls generated notes and suggestions; existing transcript text is never retroactively translated.

Transcript passages are ordered by their audio timestamps, independently of result arrival order. Revisions replace the matching unfinished range within the same source; disjoint drafts survive until finalized. A sub-sample timestamp tolerance prevents floating-point rounding from treating adjacent sentences as overlapping. Application and microphone streams share a session clock. Echo cancellation runs before speech recognition; chronological ordering remains a separate responsibility.

Live details use a native selectable text viewport containing the latest 8,192 characters. Scrolling away or selecting text pauses Follow live and holds the visible text steady while recording continues. Jump to latest, enabling Follow live, or scrolling back to the bottom displays the newest speech and resumes following. Live following stays at the bottom when the viewport resizes. Paragraph edits retain layout for unchanged text. The complete transcript remains on the worker for saving. Each source indexes revisions by timestamp, caches formatted passages, and supplies only its recent tail to the live preview; unchanged speech reuses the cached preview. Slow UI delivery coalesces progress snapshots while preserving preparation, language-change, and failure events in order.

Settings → Local AI selects the backend for notes, explanations, suggestions and writing. Foundation Models’ `SystemLanguageModel.default` is the default on supported Macs with Apple Intelligence enabled; four optional [downloadable text models](local-text-models.md) run through a separate native MLX helper. Availability is visible in the session. If unavailable or a request fails, transcripts/OCR remain saved; the Vault shows extracted highlights with a clear capability notice, without pretending those are generated explanations or inventing action items.

Each model request receives a bounded source chunk. Long sessions produce section summaries and deduplicated action items across all chunks; the start of a meeting is not silently dropped. Action extraction runs separately from summarization and retains only commitments backed by a verbatim source passage; the task is written in the selected language while preserving stated names and deadlines. Unsupported reasoning languages are explained explicitly; transcription remains available when its speech model is installed. The serial reasoning worker avoids concurrent model sessions. Source material is treated as data, not executable instructions, and there are no model tools or network services.

Participate checks new transcript material at most every 20 seconds, permits at most one accepted suggestion per 45 seconds, and keeps at most 12. Each accepted question must include a verbatim passage present in the source; repeated questions/evidence are suppressed. A nonactivating speech bubble next to the mascot shows the newest accepted question (maximum 180 characters), replacing the previous one with a finite compositor fade. Its width and height wrap the question, up to a 300-point width. Text measurement is cached until the suggestion or available screen width changes. The bubble passes every click through, supports light/dark appearance and reduced motion, stays above peer mascots and below the transcript utility window, and hides with its companion during pickup, pause, or window unavailability. Geometry and tail positioning do not rebuild SwiftUI text during movement. The mascot bar opens suggestion history and supporting evidence. Suggestions can be disabled without restarting capture; the history retains the latest 12 while new suggestions continue.

## Speaker echo processing

The bundled, pinned WebRTC AudioProcessing 2.1 / AEC3 library operates entirely on copies of captured samples; it never opens a device or renders playback. Microphone timestamps are converted from AVCaptureSession’s synchronization clock into the host clock used by ScreenCaptureKit. Both streams are converted to 16 kHz mono and paired in 10 ms frames by capture time, with 120 ms of callback holdback and fixed two-second sample rings. Missing samples become silence; invalid timestamps and unbounded discontinuities stop visibly. The meeting stream is the echo reference; the cleaned microphone remains a separate recognition channel. A half-gain mix of the two is encoded as the playable conversation recording. Record keeps its direct microphone recording path.

Pause and finish drain the remaining samples, including a partial final frame. Pause resets the sample rings, resamplers, and echo adaptation; language changes preserve the capture/AEC path. Noise suppression and automatic gain control are disabled. The processor never changes system volume, meeting mute, routing, or another app’s voice processing. Processing and encoding stay on the existing serial audio worker. Source versions, archive hashes, and licensing are documented in `Vendor/AudioProcessing/README.md`; third-party notices ship in the signed app.

## Pocket Stash and storage

Right-click a mascot → Save Clipboard, use Add text / link or Save Clipboard in the Vault, or drop text, URLs or file references onto visible mascot artwork. A hovered mascot stops ambient travel and displays Drop to save. Saving provides View and Undo; a persistence failure is shown rather than acknowledged as saved.

File entries reference original paths; Sillies does not copy those files. Stashes persist until explicit deletion. Captures default to keeping everything. An explicit retention policy can keep the latest 200, 500, or 1,000 unprotected captures; Stashes and protected meetings are exempt. Trimming deletes owned image/audio files and invalidates the search index. Writing recovery is a separate, bounded 20-result journal. Old Watch and Focus records still decode. New optional record fields preserve backward compatibility.

Storage is `~/Library/Application Support/Sillies/Vault`. AAC encoding, file finalization, PNG encoding, image decoding, OCR, speech recognition and reasoning run off the UI thread. Capture admission budgets 12 seconds per source, with a separate 4,096-callback memory cap, replacing the previous 128-callback limit. Admitted buffers drain before finalization. Apple speech callbacks are combined into 100 ms chunks with a bounded 12-second input stream. Downloadable engines use bounded rolling windows, shared weights, and serialized inference; see [local speech models](local-speech-models.md). Recognition overload stops transcription with a visible notice and keeps recording audio. Capture/DSP overload still stops capture to avoid silently losing the recording. HUD text has a fixed width and publishes at most twice per second; animation never follows per-word recognition updates.

## Validation

`make check` covers formatting, concurrency/build checks, catalog validation, interaction budgets, archive decoding, windowless microphone lifecycle, termination through the modal run loop, persistence errors, old record decoding, and stash retention.

For a real local-model workload without microphone/application capture:

```sh
say -v Samantha -r 155 -o /tmp/sillies-meeting-fixture.aiff \
  'We agreed to ship the report on Friday. Alex will review the draft tomorrow. The owner of the customer follow up is still undecided.'
SILLIES_LOCAL_AI_CHECK=1 SILLIES_SPEECH_FIXTURE=/tmp/sillies-meeting-fixture.aiff \
  bash scripts/test.sh --filter localModelsAndAACEncoding
```

This feeds a generated fixture three times into two speech streams using 10 ms input buffers, alongside notes generation and AAC encoding while exercising window move, resize, switch and companion drag budgets. It does not certify every meeting app/device combination; simultaneous live Meet/Zoom capture remains a manual acceptance check with a consenting test call.

Apple references: [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer), [on-device language model](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), [audio-input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input).

For the echo plus speech regression, generate a separate near-speaker fixture and run:

```sh
say -v Samantha -r 155 -o /tmp/sillies-near-speech-fixture.aiff \
  'I will contact the customer and confirm the deadline tomorrow.'
SILLIES_ECHO_SPEECH_CHECK=1 SILLIES_SPEECH_FIXTURE=/tmp/sillies-meeting-fixture.aiff \
  SILLIES_NEAR_SPEECH_FIXTURE=/tmp/sillies-near-speech-fixture.aiff \
  bash scripts/test.sh --filter localSpeechWithEchoCancellation
```

This feeds 24 seconds of simulated delayed speaker echo and overlapping local speech through the actual synchronization, AEC, two Apple recognizers, and AAC encoder while exercising all four interaction budgets. It checks that remote words do not appear in the microphone transcript and that the local speaker’s commitment survives. Separate deterministic tests measure echo reduction and near-speaker waveform preservation. This is not a live Meet/Zoom call or a measurement of this room’s acoustics.

### Downloadable transcription

Settings → Speech & Meetings offers Apple Speech, Whisper Turbo, and Parakeet Ultra. Downloads are explicit, include progress and pause/retry, and verify every file before publishing the installation. Models can be removed when unused. Both downloadable models support English and Romanian. Whisper offers automatic detection and an explicit language; Parakeet detects the language automatically and offers script-based language hints. Model changes apply to the next session. Speech recognition remains independent of the selected text model’s language support; automatic notes use language detection on a bounded text excerpt and fall back to extracted highlights when unavailable or generation fails.

Audio and transcripts remain on the Mac. Model files are fetched from pinned Hugging Face revisions. Downloaded-model inference uses local assets; no tokenizer fallback download is allowed. Session JSON records the provider, model, and revision while older records continue to load. Model metadata is included in Markdown export.

Settings also offers optional on-device speaker detection (up to eight speakers per source, with delayed and potentially incorrect labels), daily metadata-only model update checks, explicit update downloads with native compatibility validation, and rollback. Recording continues if speaker detection fails. See [local speech models](local-speech-models.md) for limits and short validation commands.

Everyday dictation, selection editing, paste-back, retention, and exports are described in [everyday workflows](everyday-workflows.md).
