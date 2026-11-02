# Chat model evaluation

- Use the production conversation service, prompts, tools, compaction and provider adapters.
- Model inputs contain only synthetic scenario data. Gold answers and scoring rules belong exclusively
  to the external evaluator and must never enter a prompt, tool result, or model-backed judge.
- Keep fixtures, inference execution, process deadlines, scoring and reporting separate. Adding a catalog
  model must not require a runner switch; adding a scenario must not require Swift changes.
- Every scenario owns fresh temporary Vault and conversation storage. Never open the user's Vault,
  change their selected model, or launch windows. Model downloads are a separate explicit command.
- Preserve raw inputs, outputs, calls, failures, model revisions, corpus hashes and timing. Resume only
  an identical run configuration. Missing, timed-out and failed cases must not disappear from scores.
- Prefer bounded resumable batches; process deadlines must also stop a native model that ignores cancellation.
- Separate objective tool/memory checks from lexical answer anchors and human semantic review. A matching
  word alone does not establish a correct answer. Never silently change expectations to make a model pass.
- Keep app code independent of benchmark expectations. Use the same frozen cases for every compared model.
- Treat a failed app task as an integration failure until investigated. Inspect delivered prompts and roles,
  tool definitions/results, native parsing and stop reasons, context/output budgets, retrieval and persisted
  state before attributing it to a model. Preserve unresolved causes explicitly. Use separate bounded,
  controlled replays for changes; never repair scores with case-specific prompts or output filters.
