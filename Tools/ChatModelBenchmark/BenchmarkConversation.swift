import Foundation
import SilliesCore
import SilliesReasoning
import SilliesTextModels
import SilliesVault

struct BenchmarkConversation {
  private struct Session {
    let job: BenchmarkJob
    let fixture: BenchmarkFixture
    let dialogue: BenchmarkDialogue
  }
  let backend: any ConversationBackend
  let inference: BenchmarkInferenceTrace
  let events: BenchmarkEvents
  let workspace: URL

  func run(_ job: BenchmarkJob) async throws {
    try await events.emit(.caseStarted, job)
    var completed = 0
    let lifetime = TextModelLifetime()
    await backend.retain(for: lifetime)
    do {
      let fixture = try await BenchmarkFixture.create(for: job.scenario, root: workspace)
      defer { fixture.remove() }
      let dialogue = BenchmarkDialogue(
        scenario: job.scenario, fixture: fixture, session: lifetime.id)
      let session = Session(job: job, fixture: fixture, dialogue: dialogue)
      try await dialogue.prepare()
      for (index, input) in job.scenario.turns.enumerated() {
        try await turn(input, at: .init(job: job.id, turn: index), in: session)
        completed += 1
      }
      await lifetime.end()
      try await events.emit(
        .caseFinished, BenchmarkCaseResult(job: job.id, error: nil, completedTurns: completed))
    } catch {
      await lifetime.end()
      try await events.emit(
        .caseFinished,
        BenchmarkCaseResult(
          job: job.id, error: String(describing: error), completedTurns: completed))
    }
  }

  private func turn(_ input: String, at position: BenchmarkPosition, in session: Session)
    async throws
  {
    try await events.emit(.turnStarted, position)
    let context = try await session.dialogue.request(input)
    let start = ContinuousClock.now
    let trace = BenchmarkTurnTrace(start: start)
    let progress = BenchmarkProgress(start: start)
    let service = service(in: session, position: position, trace: trace)
    await inference.beginTurn()
    let outcome: Result<ChatReply, any Error>
    do {
      let reply = try await service.streamReply(
        to: context, progress: progress.receive,
        receive: {
          await trace.receivedText($0)
        })
      try await session.dialogue.accept(reply)
      outcome = .success(reply)
    } catch {
      try await session.dialogue.preserveInterrupted(
        trace.streamedText, progress: progress.snapshot)
      outcome = .failure(error)
    }
    let facts = try await session.fixture.conversations.memories(
      .init(handle: session.fixture.handle, text: "", limit: CompanionMemoryQuery.maximumResults))
    try await events.emit(
      .turn,
      await trace.result(
        position: position, input: input, outcome: outcome,
        evidence: .init(
          memories: facts, generations: inference.snapshot(), progress: progress.snapshot))
    )
  }

  private func service(in session: Session, position: BenchmarkPosition, trace: BenchmarkTurnTrace)
    -> LocalConversationService
  {
    let selected = MeasuredConversationBackend(base: backend, trace: trace)
    let fixture = session.fixture
    let profile = session.job.tools
    let staticTools: [any ConversationTool] = [
      VaultSearchTool(library: fixture.vault), VaultReadTool(library: fixture.vault),
    ]
    .filter { profile.names.contains($0.definition.name) }
    let extras = Array(BenchmarkDistractorTool.available.prefix(profile.distractorCount))
    return LocalConversationService(
      resolveBackend: { selected }, tools: measured(staticTools + extras, position: position),
      turns: .init(),
      history: .init(
        repository: fixture.conversations,
        tools: { context in
          measured(
            ConversationHistoryTools(
              conversations: fixture.conversations, memories: fixture.conversations
            )
            .tools(for: context).filter { profile.names.contains($0.definition.name) },
            position: position)
        }))
  }

  private func measured(_ tools: [any ConversationTool], position: BenchmarkPosition)
    -> [any ConversationTool]
  {
    tools.map { MeasuredConversationTool(base: $0, events: events, position: position) }
  }
}
