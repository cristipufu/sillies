# Chat identity and memory attribution

The reported conversation saved the human user's name correctly, then the mascot answered a question
about its own name using that user memory. Stored user/assistant roles were correct. No compaction had
occurred. The memory result contained a bare key/value/quote array without an explicit subject.

Memory search now returns a bounded envelope identifying the human user as its subject and labels
original excerpts as user statements. The character profile is a separate section of the instructions.
Native roles, previous tool exchanges, and saved conversations remain intact. No name-question router,
response substitution, extra classification call, or deletion of historical replies was added.

## Bounded Apple evaluation

The checks use temporary, synthetic conversations and the production five-tool service on macOS
26.7.2. They do not modify the user's history. Earlier prompt variants failed; the final run produced:

| Scenario | Observed result |
| --- | --- |
| Human introduction → human name → mascot name, Pogo | Identity assertion passed |
| Same sequence, Bolt | Identity assertion passed |
| Save human name → retrieve memory → mascot name | Identity assertion passed; replied “My name is Pogo.” |
| Earlier assistant reply already claims the human's identity | Failed; repeated the wrong identity |
| Same incorrect reply with its original, ambiguous tool result | Failed despite a newly attributed memory result |
| Saved URL → two general questions → earlier URL follow-up | Failed; unnecessary Vault searches and lost follow-up |

These are limited observations, not a reliability score. The first identity checks only establish that
the reply contains the expected companion name; they do not grade every aspect of the prose. Apple also
occasionally claimed a memory was saved without executing the write, and unnecessarily called save_memory
while answering a recall question. Those failures belong in the broader benchmark.

Identity separation improved for the tested new conversations, but recovery from an existing wrong
reply remains unresolved. The opt-in failure assertions remain enabled when explicitly requested:

```sh
SILLIES_CHAT_TOOL_CHECK=1 SILLIES_CHAT_MODEL_CHECK=1 bash scripts/test.sh \
  --filter 'appleChatKeepsItsIdentity|appleChatCorrectsAnEarlier|appleChatRechecksPreviously|appleChatAnswersGeneralKnowledgeAfterAVault'
```

The mixed-topic issue was already observed in the [earlier integration investigation](chat-reliability-2026-11-01.md).
We cannot infer from this run that every failure comes from either the model or prompting alone.
Apple's [prompt-design guidance](https://developer.apple.com/videos/play/wwdc2025/248/)
recommends clear tasks and testing actual outputs; it does not promise reliable factual or instruction
following behavior. The next benchmark must compare the same cases across providers, preserve raw
traces and failures, and distinguish tool execution, factual correctness, continuity, and latency.
