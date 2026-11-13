# Application audio capture

Listen and Participate prefer a native Core Audio process tap. `ApplicationAudioSource` selects providers;
`CoreAudioApplicationCapture` owns a serial worker and its native lifetime; `NativeCoreAudioTapSystem`
contains HAL calls. `CoreAudioTapResources` releases the resource graph in dependency order and retains
failed handles for retry. ScreenCaptureKit remains an independent provider. `AudioTranscriptionService`
owns both application and microphone capture and keeps the existing processing, echo cancellation,
recording and recognition pipeline.

## Selection and fallback

App composition injects `ApplicationAudioIdentityCheck`. It verifies the selected PID and bundle and
requires exactly one running application instance for that bundle. HAL clients must have the exact
bundle identifier and valid non-self PIDs. Only this finite client list enters an inclusive process tap;
there is no system-wide or exclusion tap and no automatic process restoration. Browser capture remains
application-wide, including other tabs. Ambiguous app instances use ScreenCaptureKit at startup.

An unsupported startup configuration may fall back only after native cleanup succeeds. Permission
denial, arbitrary errors, cancellation and runtime failures never trigger fallback. Silence is valid
input and has no effect on provider selection. If the selected app has no HAL audio clients yet,
startup uses ScreenCaptureKit. Public APIs do not reliably distinguish denied tap access from silence;
Sillies neither calls private permission APIs nor guesses from audio samples.

The app supplies `NSAudioCaptureUsageDescription`; macOS can prompt for system-audio recording when
the aggregate starts. Meeting setup does not require screen access in advance. ScreenCaptureKit can
request its own recording permission if selected. Typed native permission errors preserve their
recovery action through the live interface and saved record.

## Device data and ownership

The private aggregate uses the current output as its clock source and requests zero physical input
channels. Capture accepts exactly one input stream with packed mono native Float32 PCM, using the
aggregate input stream's actual virtual format. Other layouts use startup fallback or stop with a
recoverable runtime failure. The provider never chooses an arbitrary input buffer, which could be a
headset microphone. The independent microphone provider remains the only microphone source.

The native IO callback runs on a separate serial callback queue. It validates byte/frame bounds,
copies borrowed audio into an owned sample buffer and submits it to the existing bounded input queue.
Core Media derives frame timing from the audio format; host timestamps retain the source clock.
No DSP, recognition, disk writes or unbounded asynchronous packet jobs run in this callback.
The lifecycle worker never shares the synchronous IO callback queue, so stopping cannot deadlock it.

Property notifications suspend delivery immediately and coalesce on the worker. Output/format changes
rebuild the tap; process changes revalidate app identity and the finite client list. Suspension tickets
and capture generations prevent old events or buffers from resuming a newer stream. Pause destroys
native resources; resume verifies scope and creates fresh resources. Stop is terminal and invalidates
delivery before draining native ownership. Listener-removal failures cannot block stopping the IOProc;
failed stops retain dependent handles rather than destroying objects still used by callbacks.

## Qualification

`CoreAudio*Tests` use a fake HAL and synthetic PCM. `ApplicationCaptureRoutingTests` verify selection,
cancellation, duplicate completions and obsolete callbacks. Capture lifecycle tests retain cleanup
failures even if they arrive before Finish after the source closes. These are standard headless tests
and are included in stress and thread-sanitizer filters. No default test creates a native tap or
requests recording permission.

Live permission prompts, third-party app capture, headsets, output switching and audible echo checks
need an explicitly authorized native recording session. Passing fake-device tests does not establish
compatibility with every app or audio driver.

## Qualification result, November 13, 2026

The final candidate passed `make check` (1,218 selected tests), `make stress` (424), and
`make race-check` (466 across its instrumented batches), with discovered-test completion receipts.
Formatting, architecture validation, all 22 language catalogs, app packaging and helper self-tests
also passed. No live call, permission-prompt, headset, visible GUI or performance check was run.

An earlier sanitizer-host presentation probe crashed in Thread Sanitizer's allocator during macOS
preferences initialization, before any Sillies app/audio test bundle loaded. Its failure log remains
in `build/test-results/run-xvh91m24/presentation-makeKey.log`. The final complete run passed with
instrumentation and test-host checks unchanged; no sanitizer suppressions were added.
