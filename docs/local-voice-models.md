# Local voices and Chat

Chat is a companion skill. Start it from the skill wheel or a companion's menu, then type a message
or choose Speak. The microphone starts only after that explicit action. Done speaking finalizes the
transcript for review; Send requests a reply. Stop reply interrupts generation and playback. Finish
& Save stores the conversation in the Vault.

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

Voice-model revisions currently ship in the app catalog; daily speech-recognition update checks do not
discover voice-model updates. No weights ship inside the app. Installing a voice needs network access;
an installed, complete model runs locally without it.

See [adding a voice model](contributing/voice-models.md) for provider contracts and bounded validation.
