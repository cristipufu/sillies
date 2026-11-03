# Stored conversation validation evidence

See the [report](../../stored-conversation-scale-2026-11-03.md) for interpretation and reproduction.
All conversation content is synthetic. No recordings or personal Chat histories are included.

- `baseline/`: production UUID-join query; 100K passed, 1M failed the broad-search budget.
- `final/`: the first complete successful sequence with the direct numeric-sequence join.
  This historical directory name predates the later improvement.
- `sequence-join-repeat/`: subsequent repeat; 1M broad searches failed. Also includes the
  system-SQLite diagnostic comparing direct joins and two ways to delay fetching bodies.
- `bounded-bodies/`: final query, ranking message IDs through metadata before fetching result
  bodies and owner names. Complete 100K/1M storage, headless Chat and process recovery sequences passed.
- `native-query-follow-up.log`: first native sequence-join check on the retained 1M fixture.
- `native-bounded-body-follow-up.log`: final query's native storage and semantic regression check.
- `source-hashes.json`: final relevant source fingerprints. Run summaries record executable hashes.
- `make-check*`: full repository verification output and checked completion receipts.

Each run folder retains native completion events and verified receipts when available. Missing
`complete: true` or missing verified receipts in failed phases must not be interpreted as success.
The two diagnostic Python files record the exact read-only query investigations; they expect the
original retained synthetic database paths described by their build-directory manifests.
