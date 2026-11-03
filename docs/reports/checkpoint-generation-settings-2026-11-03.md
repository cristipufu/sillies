# Checkpoint generation settings and Gemma's rejected call

Gemma 4 12B's rejected memory-search call exposed a missing checkpoint requirement in the MLX
adapter. The installed `generation_config.json` declares `suppress_tokens: [258883, 258882]`.
Those IDs are `<audio|>` and `<image|>`. The pinned MLX Swift LM loader reads EOS IDs and stop
strings from this file, but does not apply token suppression. Our previous generation path added
no processor for it.

The [publisher's configuration](https://huggingface.co/google/gemma-4-12B-it/raw/main/generation_config.json)
declares the same mask. This is independent of the native function-call syntax described in
[Google's tool documentation](https://ai.google.dev/gemma/docs/capabilities/text/function-calling-gemma4).
The audio token came from text generation, not microphone capture or TTS.

## Reproduction and retained fix

The rejected native frame was:

```text
<|tool_call>call<audio|>_memories{query:<|"|>user_name<|"|>}<tool_call|>
```

It was emitted while correcting a synthetic saved name. No tool executed. The rendered prompt
contained the correct schemas, original user messages, successful earlier save, and native
tool-response framing. Its 1,523-token input contained no audio control token. The original failure
came from an earlier, rejected instruction experiment; the replay preserves that exact request
rather than substituting the current prompt and claiming an identical reproduction.

| Exact single-generation replay | Malformed calls | Valid `search_memories` calls |
| --- | ---: | ---: |
| Frozen helper without suppression | 5/5 | 0/5 |
| Frozen helper with checkpoint suppression | 0/5 | 5/5 |

Both use the same weights, template, prompt, tools and application sampling profile. No fixed
sampling seed was requested. These five repetitions establish a narrow reproduction and correction,
not a general model reliability estimate or an end-to-end memory score.

`CheckpointGenerationConstraints` reads bounded metadata once per loaded checkpoint, validates
token IDs against its text vocabulary, and rejects invalid declarations before loading weights.
`MLXSuppressedTokens` masks their logits with negative infinity before sampling. Native repetition
penalties still run first. Models without a suppression declaration keep their existing behavior.
No model IDs or token numbers are hardcoded in the production policy; no malformed tool name is
repaired after generation. Apple Foundation Models owns its decoder and does not use this adapter.

An explicit `--inspect-generation` helper command captures bounded rejected tool frames from supplied
synthetic requests without executing tools. It omits the separate reasoning channel. Ordinary Chat
responses and logs still carry only typed, content-free rejection diagnostics.

## Audit of all twelve pinned downloadable text models

The audit records each installed checkpoint revision, hashes of inspected files, all declared
generation fields, tokenizer EOS, and the app's three task profiles. It is source/configuration
inspection, not twelve new native-model quality evaluations.

| Setting | Finding |
| --- | --- |
| `suppress_tokens` | Confirmed missing; fixed. Only the pinned Gemma 12B checkpoint declares it. |
| EOS IDs and stop strings | Already applied by the native loader/decoder; the decoder also includes tokenizer EOS. |
| Forced tokens, beginning-only suppression, forbidden sequences and sequence bias | No active declarations in the twelve inspected checkpoints. This adapter does not claim to implement every Transformers generation option. |
| Temperature, top-p, top-k and repetition penalty | Explicit per-task app profiles override publisher recommendations. Both LFMs match their declared conversation sampling. Gemma, Nemotron and Granite have deliberate baseline differences. |
| BOS, padding and chat framing | Templates/tokenizers own prompt framing; the app's single-prompt path does not pad batches. These are not additional post-generation text fixes. |
| Context, prefill and reasoning | Explicit per-model working budgets and runtime-owned architectural behavior. Reasoning allowances share the total output ceiling; they are not independently enforced channel quotas. |

The three pinned Qwen conversions have no `generation_config.json`; their model/tokenizer EOS
metadata remains available. Ministral supplies EOS through its generation file and tokenizer.
Gemma's architecture also applies its declared attention windows, positional configuration and final
logit soft-capping in the pinned native implementation. This audit does not validate every numerical
kernel or constitute a complete audit of speech runtimes.

Publisher sampling is a candidate to measure, not a compatibility requirement to copy blindly.
The [earlier controlled experiments](chat-loop-experiments-2026-11-02.md#quality-the-five-fastest-published-models)
found no consistent gain from publisher sampling across Gemma E4B, Nemotron and Granite. Changing
task budgets or forcing a reasoning-channel ending is not justified by the suppression defect.

## Regression coverage

Packaged helper checks exercise actual GPU masking and token selection, unchanged allowed logits,
float32/float16 and batched shapes, composition with native repetition penalties, duplicate IDs,
invalid/oversized declarations, missing optional metadata, and invalid or missing vocabulary data.
The observed rejected frame remains rejected at every two-chunk split and character-by-character;
a correctly formed native call parses across the same boundaries. Production error transport does
not expose the rejected text.

The contribution guide now requires a generation-metadata audit for new models and revisions,
separate from sampling experiments. A new forced-token or forbidden-sequence declaration requires
an explicit compatibility review; existing catalog entries do not make it safe to ignore new fields.

## Full conversation control

A separate comparison uses the **current production prompt**, the same frozen release worker and
six existing synthetic scenarios (seven turns). Only the helper's suppression behavior differs.
Each turn has a 60-second deadline; no user data or running app settings are involved.

| Gemma 12B, six difficult memory/source tasks | Automated passes | Reviewed task passes |
| --- | ---: | ---: |
| Without suppression | 4/6 | 4/6 |
| With suppression | 4/6 | 5/6 |

Both configurations saved and corrected the name, honored the explicit opt-out, and respected a
chat-only search. The suppression run correctly answered the birthday question without rewriting
its original source; the baseline unnecessarily saved the retrieved fact with the question as its
new provenance. Both missed saving a preference alongside a general question. The candidate's
quoted-speaker answer, “Ivo,” passes the rubric but not the narrower narrator/character lexical check.
The evaluator was not changed to turn that into an automated pass.

Neither fresh full-conversation run reproduced the malformed call. They therefore provide a small
regression control, not proof that suppression improves semantic decisions. One observation per task,
unmatched sampling and differing generated history cannot establish a general quality gain. The
exact-input decoder replay above isolates the original malformed-frame failure more directly.

## Gemma 12B sampling control: rejected

Two unresolved decision inputs from the fresh baseline were frozen: the initial preference/general
question, and the birthday turn immediately after memory search. Each was replayed three times with
the suppression helper. Tools do not execute in these probes. The only changed input was conversation
sampling: app temperature 0.7/top-p 0.9/top-k disabled/repetition penalty 1.08 versus the publisher's
temperature 1/top-p 0.95/top-k 64/no declared repetition penalty. The output ceiling stayed at 240.

| Single-generation decision | App profile | Publisher sampling |
| --- | --- | --- |
| Save the stated preference alongside the general question | Missed in 3/3 | Missed in 3/3 |
| Answer from the retrieved birthday without writing it again | 2 direct answers; 1 unnecessary save call | 1 direct answer; 2 output-token-limit failures |

Both publisher failures used the output allowance in the hidden reasoning channel (zero visible
response bytes). These are typed failures, not leaked reasoning or UI crashes. They do not justify
force-closing a channel, enlarging every model's output allowance, or applying this sampling change.
No sampling profile or prompt changed. The narrow probes are diagnostic, not full-conversation
scores, and do not establish an optimal profile.

## Evidence and limits

- [Native replay, settings audit and sampling inputs/outputs](data/checkpoint-generation-settings-2026-11-03/native-inspection.json.gz).
- [Production-prompt baseline](data/checkpoint-generation-settings-2026-11-03/memory-baseline.json.gz) and its [evidence audit](data/checkpoint-generation-settings-2026-11-03/memory-baseline-audit/audit.json).
- [Production-prompt suppression control](data/checkpoint-generation-settings-2026-11-03/memory-suppression.json.gz) and its [evidence audit](data/checkpoint-generation-settings-2026-11-03/memory-suppression-audit/audit.json).

Runs used release binaries and synthetic temporary stores on one Mac. Every inspected checkpoint
metadata file matches its pinned manifest hash and size. Binary/input hashes and model revisions are
retained. Native candidates were frozen before additional metadata/float16 self-check assertions
and an actor-based diagnostic observer; the masking and sampling policy is unchanged. The final
packaged helper also replayed the original request successfully. Reviews were performed by the
implementing agent, not an independent blinded reviewer. These evaluations did not replace
leaderboard scores or restart the running app.

Final `make check BUILD_DIR=/tmp/sillies-suppression-check` passed: completion receipts verify 707
headless native tests across 18 runs, plus 92 tooling tests, packaged GPU/protocol checks, parent-exit
checks, catalog validation and localization extraction. See the [validation receipt](data/checkpoint-generation-settings-2026-11-03/validation.json)
and [full check log](data/checkpoint-generation-settings-2026-11-03/validation.log.gz). Visible GUI
checks were not run; this change does not modify windows or presentation.
