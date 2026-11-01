# Chat reliability investigation — 1 November 2026

## Status

The duplicate-card and native text-sizing defects have code fixes and headless regressions.
The Apple model's mixed general-conversation/Vault behavior is **not fixed reliably**. Real-model
evaluations remain in the repository as opt-in checks, with both successes and failures recorded below.
No extra classifier, tool-removal
policy, keyword router, answer substitution, or new output guard is included.

## What Apple's API expects

- `LanguageModelSession` is stateful. Tool calls and outputs are normal transcript entries and remain
  available to later turns. Reusing the session is the normal multi-turn path.
  [WWDC25 introduction](https://developer.apple.com/videos/play/wwdc2025/286/),
  [Tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling).
- Stable instructions, tools and history preserve the native cache. Removing a tool while retaining
  references to it can cause unexpected output; removing history can also lose constraints and facts.
  [Session and cache guidance](https://developer.apple.com/documentation/foundationmodels/optimizing-key-value-caching-in-language-model-sessions).
- Apple recommends concise instructions and testing prompts against the actual on-device model.
  Multiple requests add latency; splitting a task is an option, not an API requirement.
  [Prompting guidance](https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model).
- Apple's on-device model has limited world knowledge. A correct response to one factual question
  does not establish broad factual reliability.
  [WWDC25 prompt design](https://developer.apple.com/videos/play/wwdc2025/248/).

The installed SDK exposes per-request `toolCallingMode`, but marks it macOS 27+. It is unavailable
on the tested macOS 26.7.2 system. The default `allowed` mode documented for the newer API preserves
existing behavior; it does not itself decide which questions need personal records.

## Evidence and limits

1. The saved Pogo transcript contains the reported transition from Vault questions to a general
   mountain question, followed by a refusal to answer. Saved chat records do not include the transient
   live-card rendering state, so that UI defect was traced in code and reproduced with controlled
   progress delivery rather than inferred from the archive alone.
2. Plain Apple sessions without tools answer the mountain and photosynthesis questions correctly.
3. A standalone native Swift example, independent of Sillies, reproduces unnecessary personal-record
   searches and empty-search answers with a persistent Apple session. Both greedy and default sampling
   were tried. Clearer personal-record tool naming did not eliminate it. The native transcript was
   inspected: matching call/output IDs, valid roles, string tool output and registered definitions.
   Its initial prompt and tools differed from the app, so this alone was not a controlled comparison
   and did not identify the cause of the reported application failure.
4. Concise/conditional prompts improve some cases but do not reliably pass the mixed-topic sequence.
   Native guided generation was also tried outside the application; it repeated lookups until the
   fixture's bounded tool budget stopped it.
5. An experimental classifier added roughly 0.4–0.8 seconds before the reply and initially misclassified
   a meeting request. It was removed. An experiment that removed tools while retaining their old entries
   produced unreliable replies and a native generation error. That experiment is not evidence that
   ordinary, correctly registered tool history is invalid.
6. Qwen 3.5 2B was also tried with the same temporary Vault and existing isolated helper. It did not
   consistently perform the initial retrieval; one run returned an incomplete response. It is not a
   validated replacement based on this check. Larger models were not downloaded for this investigation.

These checks use synthetic records. They make no network requests from the model, transmit no user
conversation, and add no third-party runtime dependency.

## Controlled native/application comparison

`AppleChatIntegrationTests.swift` uses the application's actual instructions, tool definitions,
tool implementation and temporary saved URL. Two fixed record IDs and a fixed creation timestamp
make the fixtures reproducible. It compares retained native history, restoration from the exact
native `Transcript` value, reconstruction from canonical app messages, and streamed/completed
responses. The application adapter asserts equality of instructions, messages, tools, style and
response-token limit before passing the request to Apple. Every native branch uses greedy sampling
and a 240-token response limit.

Latest completed run on macOS 26.7.2, with both fixed fixtures:

| Path | Input tokens | General question | Later reference to the saved URL |
| --- | ---: | --- | --- |
| Fresh native session, app instructions, no tools | 328 | Answers Everest | Not tested on this branch |
| Fresh native session, same instructions, tools registered | 780 | Searches Vault; says it has no information | Not tested on this branch |
| Retained native session after URL retrieval | 1,006 | Answers Everest without a tool call | Recovers the earlier URL |
| Restored exact native transcript | 1,006 | Same behavior as retained native session | Recovers the earlier URL |
| Reconstructed app transcript | 1,006 | Same behavior in this run | Recovers the earlier URL |
| Streamed exact/native and reconstructed histories | 1,006 | Same behavior as completed responses | Not tested on these branches |
| Application adapter, same canonical request | Not separately counted | First fixture searches unnecessarily; second answers Everest | Not tested on this branch |
| Full application continuation | Not separately counted | Answers Everest without a tool call | Covered separately by the mixed-topic check |

The full application continuation counts creation of actual `NativeAppleChatSession` instances,
not a fake backend. Both fixtures create **one** instance across initial retrieval and the next
question. This verifies that the completed tool turn survives committing the reply and passes the
continuation comparison in the real service path.

Earlier runs varied: in one fixed-fixture run the reconstructed branch searched unnecessarily while
the retained native branch answered directly; another run produced unnecessary searches with both
response APIs. The latest adapter mismatch also occurred despite matching canonical request fields.
The successful branches therefore do not establish a reliable quality fix, nor prove that native and
reconstructed histories always produce equivalent answers. No streaming-specific defect or precise
model-internal cause has been isolated. Native response metadata, generated call IDs and model
nondeterminism have not been independently controlled.

The fresh-session failure establishes that previous tool results are **not required** to reproduce
the unnecessary search with the app's prompt and tools. The successful follow-ups establish that
valid native tool history is usable. Neither result justifies stripping history or adding a second
classification request as an API workaround. Registered-tool availability changes the model's input;
the experiment does not distinguish model behavior from every possible prompt/tool-design effect.

Reproduce without opening windows or reading the user's Vault:

```sh
SILLIES_APPLE_CHAT_COMPARISON=1 bash scripts/test.sh \
  --filter appleNativeAndApplicationTranscriptsUseIdenticalChatInputs
SILLIES_CHAT_MODEL_CHECK=1 bash scripts/test.sh \
  --filter appleChatAnswersGeneralKnowledgeAfterAVaultConversation
```

The comparison asserts request equivalence, follow-up continuity and native session reuse. It logs
model answers instead of asserting that every branch makes the correct search decision. The separate
mixed-topic test asserts answer quality and absence of irrelevant searches. It failed earlier and
passed in the latest run without another production change. Neither its latest pass nor the comparison
passing erases the unnecessary searches still observed in other branches.

## Changes retained

- Preserve a completed Apple native session after tool use. Validate continuation against the exact
  canonical dialogue and executed exchanges, rebind the current toolbox, and invalidate on errors,
  pressure, owner end or changed context. This avoids unnecessary rebuilds; it does not claim to fix
  model tool-selection quality.
- Shorten the chat instructions and distinguish general conversation from personal-record lookup.
  Clarify tool descriptions and generate category before topic keywords.
- Include the whole-Vault count separately from the bounded search-page count, with stable encoding
  for full and brief output. Counting does not load record bodies.
- Give live cards a stable reply owner. Repeated retrieval keeps evidence but does not duplicate the
  same cards under later replies. Failed and late deliveries remain retryable and cannot cross turns.
- Measure chat text with a separate TextKit layout. Speculative width queries no longer change the
  displayed text view's layout. Follow the bottom after content geometry updates, respecting selection.
- Use 16-point rounded system text with additional line and paragraph spacing, consistent across
  measurement and drawing. Light/dark previews were rendered offscreen.

## Validation

`make check BUILD_DIR=/tmp/sillies-chat-fix-check` passed: 569 selected tests across 18 runs, formatting,
architecture/localization checks, helper self-checks and helper parent-exit checks. No visible GUI
suite or running-app restart was performed.

Focused regressions cover speculative sizing, unfocused streaming, Unicode, selection, repeated
sources, a fresh conversation, delayed progress after failure, retries and stale updates. These verify
concrete layout/state defects; they do not prove the entire intermittent on-screen blanking symptom
is eliminated without an interactive reproduction.

The native Apple screenshot/link/meeting retrieval check passes. The final real-model run completed
the two-fixture integration comparison in 52.552 seconds and the mixed-topic quality check in 9.836
seconds. The latter answered both general questions without tools and recovered the earlier saved URL.
Its earlier run failed both general questions. The final comparison still recorded incorrect searches
in both fresh-with-tools fixtures and the first reconstructed application-adapter fixture. These failures
must remain visible when assessing readiness; passing default code tests or one conversation sequence
is not a substitute for reliable model behavior across cases.
