# Add a text / LLM model

Text providers generate bounded results for meeting notes, explanations, suggestions, and writing.
They are selected independently of speech recognition. A model supported by the existing MLX runtime
can use the catalog and installer; a new runtime needs a separate adapter.

## Add a compatible MLX model

1. Confirm that the pinned MLX runtime supports the architecture, quantization, tokenizer, and chat
   template. Review the upstream license and device requirements. Do not load remote executable code.
2. Add its pinned repository/revision and display/hardware metadata to `scripts/update-text-catalog.py`.
   Generate `Sources/SilliesModelStore/Resources/text-models.json`. Review all required files, hashes,
   byte lengths, license information, and the total download size.
3. Run catalog validation and the helper's tokenizer check against the installed local files. A custom
   tokenizer may need an adapter; successful tokenization alone does not prove generation quality.
4. Update catalog regression expectations and packaged attribution. Keep IDs stable and revisions
   immutable. Reuse the shared settings rows and installer rather than adding per-model UI branches.
5. Evaluate the actual tasks and languages you intend to advertise. Include English, Romanian,
   mixed-language passages, names, dates, numbers, identifiers, and incomplete or malformed output.

After editing the generator, regenerate and inspect the manifest:

```sh
python3 scripts/update-text-catalog.py
git diff -- Sources/SilliesModelStore/Resources/text-models.json
```

This maintenance step fetches upstream metadata and small support files, not model weights. Review
the generated license, artifact selection, and context limits; existing generator defaults are not
automatically appropriate for a new model family.

Downloads use `ModelArtifactManifest` and `ModelStore`; provider selection uses `TextModelRegistry`.
Downloading does not automatically select a model. Text-model revisions currently ship with the app;
the speech-model update mechanism does not discover text-model updates.

## Add another runtime

1. Implement `TextModelProvider.prepare` and `PreparedTextModel.generate/complete/stream/stop` in `SilliesTextModels`'s
   contract. Requests and results use the shared text types. Register the provider once in
   `App/Composition/ReasoningServices` and reference its provider ID from the catalog.
   Features receive `LocalReasoning`; never construct a runtime or reach for a shared service there.
2. Isolate the heavy SDK and native inference in a helper target. Keep those imports out of the app.
   Reuse bounded IPC, request deadlines, cancellation, crash recovery, and explicit asynchronous teardown.
3. Integrate with `SilliesInference.InferenceActivity`: interactive speech takes priority, and background
   notes must yield. Keep one downloaded model loaded at a time and release it when idle or stopped.
4. Reuse storage, installation leases, selection, and resource limits. Add helper resources and licenses
   to `scripts/build-app.sh`. Keep task prompts and output validation in `SilliesReasoning`.
5. Respect each consumer's deadline. In particular, late dictation cleanup must never rewrite a field
   after the finalized transcript has already been inserted.

These are source integrations, not user-installed executable plugins. Adding a compatible model should
not change audio capture, transcript rendering, character behavior, or window tracking.

## Native conversations and tools

For Chat, also implement the `ConversationBackend` capability with native message roles, tool calls,
and token measurement. The helper must distinguish generation from measurement and preserve typed
context-limit errors over IPC. Do not encode history into a single user message. Verify the model's
actual tool format with the pinned runtime. See [Chat tools and context](chat-tools.md).

## Streaming contract

`stream` awaits a `TextDeltaSink` and returns the final `TextGenerationOutput`. Deltas contain only
new user-facing text. The final text must match their concatenation after boundary whitespace is
trimmed. Keep native tool calls out of the text sink; return them as typed calls. A final answer must
never replace text that may already have been spoken. Nonstreaming adapters have a whole-result
fallback, but should implement `stream` when their runtime supports it.

Apple converts cumulative snapshots through `TextStreamSnapshot`; MLX forwards parsed text chunks.
`TextStreamBatch` coalesces small tokens without timers. Worker frames require acknowledgement after
consumer delivery, have byte limits, and share a total request deadline. Cancellation kills and reaps
the helper. Both inference helpers also terminate when their parent exits.

Carry `conversationID` through tool rounds and synthesis requests. The inference scheduler permits
text and voice for the same turn to overlap only within its conservative combined memory budget.
An oversized voice waits for text to finish, then the text helper is evicted before voice preparation.
Cached idle peers also count. Background work retains lower priority; recognition preempts both.
These estimates leave headroom but are not a measurement or guarantee of peak resident memory.

Once any text has been delivered, preemption or context overflow must not automatically regenerate
it. Preserve the partial response and expose explicit recovery. Before first delivery, the existing
single context-recovery attempt remains available. Add tests for multi-chunk delivery, cancellation,
worker exit, final-text mismatch, tool calls, and overflow after a delivered prefix.

## Check it

Run `make check BUILD_DIR=/tmp/sillies-check`, plus relevant cancellation, failure, priority, and
concurrency checks. Default checks must not fetch weights. Exercise the packaged helper as well as
contracts: development-only execution does not prove the app has all its runtime resources.

Follow the [bounded validation procedure](../local-text-models.md#bounded-verification) to test real
weights with short fixtures. Separate preparation from inference, report cold and warm behavior,
and distinguish tokenizer compatibility, runtime success, and output quality. Put semantic mistakes
in shared evaluation fixtures; avoid one-off rules for specific words or weekdays.

`TextModelBenchmark stream MODEL_ID MODEL_DIRECTORY` exercises real acknowledged deltas in an
initial and a reused helper, reporting first-text and total latency separately. Set
`SILLIES_TEXT_HELPER` to the packaged executable when validating a built app. This mode uses a
synthetic greeting, no user records, and does not download weights.

See [runtime ownership and limits](../local-text-models.md) and [the development contract](../../AGENTS.md).
For audio-to-text, use the [speech-model guide](speech-models.md).
