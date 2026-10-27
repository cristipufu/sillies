# Companion skills

The wheel and the mascot's context menu expose the same five actions. Hover over a target window while dragging to reveal the wheel, move to a bubble, then release. Without a choice, the mascot returns quietly and preserves any running skill. Record is also in the menu bar and needs no selected window.

| Skill | Input | Result |
| --- | --- | --- |
| Listen | Selected application's output audio | Live local transcript, summary, explicit action items |
| Participate | Selected application's output **and microphone** | The same notes plus optional, quiet meeting questions |
| Snap | One selected window image | PNG on clipboard and in the Vault; no OCR/model delay |
| Explain | One selected window image | PNG, Vision OCR, summary and plain-language explanation of the recognized text |
| Record | Built-in microphone where available; otherwise default microphone | Playable `.m4a` AAC file, local transcript, summary and action items |

ScreenCaptureKit's audio filter is application-wide. Selecting a Google Meet browser window includes audio playing in other tabs of that browser. Sillies does not claim per-tab isolation. Microphone speech is labeled separately from app speech; these are source labels, not speaker diarization. Headphones prevent meeting audio from being picked up a second time by the microphone. Explain reasons over OCR text, not invisible content or the visual meaning of images alone.

## Capture and meeting apps

ApplicationAudioSource only subscribes to ScreenCaptureKit audio. MicrophoneAudioSource uses an independent AVCaptureSession, prefers a device with built-in transport, and never locks a device for configuration. There are no system-device, format, volume, mute, routing, virtual-driver, meeting-UI, or voice-processing changes. The app has the hardened-runtime audio-input entitlement; macOS permissions are still required. Capture is never started on launch or by hovering.

Participate requires both inputs to start successfully. A failed or interrupted input produces an explicit stopped state, stops the capture producers, and lets the user save the partial transcript. It does not silently continue as a complete meeting recording. One audio session is allowed across the crew, including while it is finishing.

Muting Meet or Zoom does not mute Sillies' independent microphone. Its transcript label is **Microphone**, since laptop speakers can also enter that input. Sillies does not perform acoustic echo cancellation. Use headphones for Participate, or Listen when only meeting output is needed.

All audio modes share preparing, capturing, paused, finishing, failed, and finished presentation. Pause discards incoming audio without saving/transcribing it, while keeping input access ready for Resume. Finish stops sources, drains transcription, closes the AAC container, then writes the Vault record. There is a bounded eight-second speech-finalization deadline; a timeout preserves available text and reports the limitation. Audio skills start with the transcription window closed. Open it explicitly from the mascot bar, context menu, or control center; closing it keeps capture running. This utility window accepts typing and language selection but is excluded from companion attachment and skill drop targets, including native focus/move/resize notifications. Pausing the app, an exclusion, removing the companion, and termination all stop the session and retain partial work.

Termination completions use MainRunLoopDelivery (common and modal-panel modes). Capture finalization does not rely on the main actor task executor being drained by AppKit's termination modal loop.

Bound mascots and their bars share the target window's native level and order immediately above it. They hide when that window is offscreen, minimized, or completely covered, retaining their binding and attachment slot while capture continues. The existing skill refresh reads one bounded window-metadata stack on a worker; coverage is rectangular metadata, not pixel inspection. The transcription utility window appears above mascots and bars and remains excluded as an attachment target.

## Local processing

Sillies requires macOS 26 or later. SpeechAnalyzer/SpeechTranscriber handles long-running speech, using two independent channels for Participate. The Spoken language menu lists system-supported locales and distinguishes models already installed on this Mac from unavailable ones. Sillies never requests a model download. Recognition requires an explicit locale; it does not infer the spoken language from audio. No remote recognition fallback is enabled. SpeechAnalyzer does not require the older Speech Recognition authorization; microphone and system-audio permissions still apply.

The remembered installed language is used at startup; otherwise Sillies chooses an installed match for the device language. If neither is available, the mascot bar asks the user to open the transcript and choose a ready language. Changes affect new speech, preserve earlier text, and switch both Participate channels together. Audio capture and the recording file remain open while recognizers change; bounded buffering bridges the switch. A paused session remains paused. The final selection is saved with the record and controls generated notes and suggestions; existing transcript text is never retroactively translated.

Transcript passages are ordered by their audio timestamps, independently of result arrival order. Revisions replace the matching unfinished range within the same source; disjoint drafts survive until finalized. A sub-sample timestamp tolerance prevents floating-point rounding from treating adjacent sentences as overlapping. Application and microphone streams share a session clock; this ordering does not remove speaker echo across inputs.

Foundation Models' `SystemLanguageModel.default` supplies on-device notes, explanations and suggestions on supported Macs with Apple Intelligence enabled. Availability is visible in the session. If unavailable or a request fails, transcripts/OCR remain saved; the Vault shows extracted highlights with a clear capability notice, without pretending those are generated explanations or inventing action items.

Each model request receives a bounded source chunk. Long sessions produce section summaries and deduplicated action items across all chunks; the start of a meeting is not silently dropped. Action extraction runs separately from summarization and retains only commitments backed by a verbatim source passage; the task is written in the selected language while preserving stated names and deadlines. Unsupported reasoning languages are explained explicitly; transcription remains available when its speech model is installed. The serial reasoning worker avoids concurrent model sessions. Source material is treated as data, not executable instructions, and there are no model tools or network services.

Participate checks new transcript material at most every 20 seconds, permits at most one accepted suggestion per 45 seconds, and keeps at most 12. Each accepted question must include a verbatim passage present in the source; repeated questions/evidence are suppressed. A paw indicator opens the suggestions, without automatic popups or sending anything into the meeting. Suggestions can be disabled without restarting capture.

## Pocket Stash and storage

Right-click a mascot → Save Clipboard, use Add text / link or Save Clipboard in the Vault, or drop text, URLs or file references onto visible mascot artwork. A hovered mascot stops ambient travel and displays Drop to save. Saving provides View and Undo; a persistence failure is shown rather than acknowledged as saved.

File entries reference original paths; Sillies does not copy those files. Stashes persist until explicit deletion. The 200-record history limit applies to other skill records and removes their owned image/audio files. Old Watch and Focus records still decode. New optional record fields preserve backward compatibility.

Storage is `~/Library/Application Support/Sillies/Vault`. AAC encoding, file finalization, PNG encoding, image decoding, OCR, speech recognition and reasoning run off the UI thread. Capture admission budgets 12 seconds per source, with a separate 4,096-callback memory cap, replacing the previous 128-callback limit. Admitted buffers drain before finalization. Variable speech callbacks are then combined into 100 ms chunks, giving each recognizer a separate bounded 12-second input stream. Overload stops with a visible partial-session message. HUD text has a fixed width and publishes at most twice per second; animation never follows per-word recognition updates.

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
