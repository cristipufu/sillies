# Local voices and Chat

Chat is a companion skill. Start it from the skill wheel or a companion's menu, then type a message
or choose **Voice**. Return sends a typed message; Shift–Return adds a new line. Voice starts an
explicit conversation: speech detection finalizes and sends each utterance after a natural pause,
and the microphone stays live during replies so you can interrupt. **Send now** ends a turn early;
**End voice** stops capture and keeps unfinished words in the composer. Closing the Chat window also
ends voice mode. **Finish & Save** stores the conversation and any unsent words in the Vault.

The compact messenger window uses the companion's portrait and selectable message bubbles. Reading
older messages or selecting text holds your place; **Latest** returns to the conversation's end.
Opening and closing use short native transitions and respect Reduce Motion.

Settings separates three choices:

- **Speech & Meetings** recognizes your speech.
- **Local AI** generates the written response.
- **Voices** optionally reads the response aloud.

Text replies remain available if no voice is selected, a language is unsupported, or generation fails.
Choosing a different model takes effect on a later request. Downloading does not select a model.

| Provider | Native runtime | Language support | Voice selection |
| --- | --- | --- | --- |
| Kokoro | FluidAudio / Core ML | English in the supported pack | 12 supplied voices |
| Pocket TTS | FluidAudio / Core ML | English in the supported pack | 8 supplied voices |
| Qwen3-TTS | Argmax TTSKit / Core ML | Chinese, English, French, German, Italian, Japanese, Korean, Portuguese, Russian, Spanish | 9 supplied voices |
| Fish S2 Pro | Sillies / Apple MLX | [Publisher's supported languages](https://huggingface.co/fishaudio/s2-pro#supported-languages); the full list appears in Settings | Automatic voice; may vary between replies |

Companion personality and preferred provider voices live in character JSON (`chat.personality`,
`chat.languageIdentifier`, `chat.preferredVoices`). The conversation language can be changed before a
turn. Runtime support can be narrower than a base model's training-language list. Model licenses
remain separate from the app's MIT license; see [third-party notices](../THIRD_PARTY_NOTICES.md).

Voice inference runs in a separate process with bounded messages and killable cancellation. Playback
buffers at most 0.75 seconds ahead, and its amplitude drives native mouth/head animation. No mascot
owns an inference model, audio engine, or animation timer. One downloaded voice model is loaded at a
time and released after inactivity. Recognition takes priority over synthesis and background text work.

Chat uses the existing local WebRTC AEC3 echo canceller and WebRTC voice detection. The reference comes
from rendered Sillies audio, aligned with the microphone on the host clock. DSP runs on the capture
worker; recognizers acquire speech-model priority per utterance. This leaves text and voice inference
available between turns without pausing the microphone. Echo cancellation is not speaker identification:
another person in the room may start a turn, and clipping or unusual routing can impair cancellation.

Conversation generation uses conversational sampling rather than extraction settings. A general
repetition guard rejects sustained output loops with a retryable error before displaying or speaking
them. Responses remain model-generated and may be inaccurate.

Voice-model revisions currently ship in the app catalog; daily speech-recognition update checks do not
discover voice-model updates. No weights ship inside the app. Installing a voice needs network access;
an installed, complete model runs locally without it.

See [adding a voice model](contributing/voice-models.md) for provider contracts and bounded validation.

## Short local checks

`make check`, `make stress`, and `make race-check` cover turn boundaries, bounded queues,
interruption, late/duplicate callbacks, final-word recovery, native editing, and window lifecycle.
An optional accelerated speech/echo fixture exercises the actual AEC and VAD without recording a
microphone. It runs seconds of sample time without waiting for real-time playback:

```sh
say -v Samantha -o /tmp/sillies-chat-echo.aiff 'Hello there. What would you like to talk about today?'
say -v Samantha -o /tmp/sillies-chat-echo.aiff.near.aiff 'Wait, I have a different question. Can we discuss tomorrow?'
source scripts/toolchain.sh
swift build --build-tests
SILLIES_VOICE_ECHO_FIXTURE=/tmp/sillies-chat-echo.aiff \
  python3 scripts/run-bounded-test.py 90 swift test --skip-build --no-parallel \
  --filter voiceConversationEchoReference
```

`SILLIES_NATIVE_PLAYBACK_CHECK=1` enables `playbackRenderReferenceUsesTheDeviceClockAndStopsWithOutput`,
a silent, subsecond output-device check. `SILLIES_CHAT_MODEL_CHECK=1` enables
`appleChatHandlesTheReportedConversationWithoutRepeating` on Macs with Apple Intelligence ready.
Neither check downloads weights. Fixture results do not substitute for testing loudspeaker volume,
room acoustics, and interruption on the intended device.
