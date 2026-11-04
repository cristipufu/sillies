# Prefix profile qualification

The registered limits and decisions are in [study.json](study.json). The same frozen worker,
helper, evaluator, corpus and production sampling profiles were used in both arms; the candidate
changes only the four models' cache policy and snapshot caps. Seeds 11 and 29 initialize a fresh
native sampler for each generation. They control sampling variation without promising identical
answers when native floating-point computation changes shape.

All four profiles remain disabled. No new model failed an expected memory write that its paired
baseline completed: every arm missed the new-name writes. However, full-answer review found other
differences that aggregate case counts concealed. The follow-up audit found that several highlighted
failures occurred with zero reused tokens. This small screen did not establish an overall quality
reduction caused by state reuse. See the [report and audit clarification](../../../../../docs/reports/search-memory-and-prefix-profiles-2026-11-04.md).

The quality gate stopped further activation work. Unrun warm timing, invalidation, lifecycle and
capacity gates are **not passed**. Native diagnostic state restoration was exact for all four
models; ordinary unsplit prefill differed numerically. No tuning on test answers was attempted.
