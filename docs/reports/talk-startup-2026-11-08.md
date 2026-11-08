# Talk startup investigation

November 8, 2026. A live Talk session using Parakeet Ultra remained in preparation for 43 seconds
before the user stopped it. A later process sample still showed the original encoder load waiting
for the Neural Engine compiler. This was background work; the sample did not show a blocked UI thread.
The measurements below used an M4 Pro with 48 GB RAM and macOS 26.7.2.

## Findings and changes

- The label said the microphone was preparing, although speech weights were still loading. Talk now
  displays the producer's actual speech/device preparation stage.
- Awaiting a shared preparation task did not return when its consumer cancelled. The registry now
  completes that consumer independently. Other consumers retain their preparation; a cancelled
  native load occupies one slot until it returns, so retries cannot spawn duplicate compilations.
  Cancelled results never enter the cache. Apple's runtime can still prepare independently.
- Cancelling speech admission now releases that waiter even when an earlier native operation has
  not drained. Already-cancelled requests do not interrupt a reply.
- Talk startup has a 45-second deadline. Failure stops capture, preserves the appropriate recovery
  category, and rejects late completion. Successful startup and explicit stop cancel the deadline.
- Parakeet's encoder uses CPU, with a short silent validation pass before capture. The small
  preprocessor, decoder and joint retain their existing runtime configuration. All work remains
  off the main queue. This uses existing Core ML and FluidAudio dependencies.
- Content-free diagnostics identify recognition preparation start, completion, cancellation and
  failure using the operation ID. They retain no words, audio, paths or device names.

## Bounded native experiments

The same installed Ultra revision (`95eaa59a39d4394f047a4dc5cce480388a60d1b6`) and native benchmark
were used. Files were generated with installed macOS voices; no microphone was opened. The probes
were limited to 45–90 seconds each. No OS compilation cache was cleared, so these are observed
startup costs, not a controlled comparison of completely cold devices.

| Candidate | Observed preparation | First speech finalization | Decision |
|---|---:|---:|---|
| Existing Neural Engine encoder | Still waiting in the compiler after cancellation | Not reached | Replace the encoder placement |
| GPU encoder | Encoder-only probe 6.83 s; full runtime 12.93–17.38 s | 12.92–31.38 s | Reject: load success did not imply readiness |
| GPU plus silent warm-up | Exceeded the bounded probe; sample showed MPSGraph specialization | Not reached | Reject |
| CPU encoder, without warm-up | 38.18 s | 2.18 s | Useful control; still prepare prediction before listening |
| CPU encoder, with warm-up, first run | 17.60 s | 0.30 s | Retain |
| CPU encoder, with warm-up, next process | 0.69 s | 0.40 s | Retain |

The first GPU runtime test overlapped part of a separate startup check; it is not an isolated latency
comparison. An isolated repeat still had a 12.92-second first finalization. The CPU warm-up runs were
sequential. Their second-language fixture finalized in 0.22 and 0.21 seconds. English words were
preserved, with punctuation differences. The second-language sample retained diacritics but
misrecognized a name; successful execution is not proof of perfect recognition. These short
synthetic samples do not replace broad language accuracy or multi-Mac performance evaluation.

The CLI's main-actor scheduling probe includes timer wake-up delay. It is not a native frame-time
measurement. CPU placement leaves the GPU available to the compositor, but these runs do not prove
all display frames meet their budget or establish energy use across Mac models.

## Validation

Deterministic regressions cover uncooperative model preparation, cancellation of one consumer versus
shutdown, no duplicate native loads, rejection of cancelled results, startup timeout, late device
callbacks, deadline cancellation, correct status/recovery, and admission release. An opt-in headless
integration check loads actual installed weights through the conversation warm-up chain and reaches
listening with a fake microphone. Required tests verify completion receipts.

The final CPU/warm-up integration run reached listening in 29.63 seconds, stopped the fixture
microphone once, and allowed text inference afterward (`run-l6a4hkk9`). This separate test host had
more preparation work than the repeated CLI process. First use must therefore retain truthful
progress and cancellation; the subsecond CLI repeat is not a promise of subsecond startup everywhere.

The final focused run verified 18 tests across five runs (`run-nujaamgd`). Broader checks also exposed
redundant character traversal in transcript previews: whole passages were truncated despite their
cached lengths already fitting the preview. Only the boundary passage is now truncated. All 186 core
tests passed, including the original 4 ms publication budget and Unicode boundaries. No performance
threshold was changed.

Audio DSP, persistence scale, native app workflows, and the remaining modules now have separate
bounded test batches. Previously their combined run could consume its deadline before storage tests
finished. A runner regression verifies complete, disjoint coverage, including future test targets.
Completion receipts remain mandatory.

The same 18 focused regressions also passed under Thread Sanitizer across five verified runs
(`run-a5fp5o3l`), with no race reports. The Developer ID-signed app was restarted successfully with
the fix. No real microphone capture or visible GUI test was started during verification.

The subsequent native-voice integration ran `make check` again and verified all **1,100 selected
tests**, plus lint, architecture, localization, packaged-helper self-tests and parent-exit checks.
The earlier 4.17 ms transcript-publication result remains in its original log; no timing threshold
was increased. Broader stress/race validation is **not all green**:

| Check | Remaining result |
|---|---|
| `make check` | Passed on the subsequent complete run; receipts `run-j8sqdd0q`, `run-iug0b_b_`, `run-x9hn0sza` and `run-nk54p_pu`. |
| `make stress` | The synthetic 600-second encoding fixture reached its 60-second work deadline and cancelled, followed by the aggregate runner deadline. |
| `make race-check` | The broad instrumented batch reached its aggregate 90-second deadline. The affected startup/cancellation components then passed in the separate focused run above. |

The stress/race failures are retained in the local logs. They are not waived by the successful
focused checks or the later `make check` run.

The native compiler itself cannot be forcibly cancelled in this in-process speech adapter. Cancelling
the app's waiter does not claim to terminate that system work. Retaining its one occupied slot keeps
work bounded until completion; moving speech inference to a killable helper would be a separate
architecture change.

## References

- [FluidAudio's upstream discussion of Ultra specialization](https://github.com/FluidInference/FluidAudio/issues/1022)
- [Apple's explanation of loading, specialization and first prediction](https://developer.apple.com/videos/play/wwdc2023/10049/)

Local experiment logs and samples are under `build/bolt-microphone-investigation/` and are not bundled
with the app.
