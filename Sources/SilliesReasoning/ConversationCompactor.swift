import Foundation
import SilliesCore
import SilliesTextModels

/// One bounded generation per checkpoint. Failure never advances the durable source cursor.
struct ConversationCompactor {
  let backend: any ConversationBackend

  func compact(_ messages: [ChatMessage], into memory: ConversationMemory) async throws
    -> ConversationMemory?
  {
    let source = try boundedSource(messages)
    let ends =
      source.indices.filter { $0 > 0 && source[$0].role == .user }
      + (source.last?.role == .companion ? [source.count] : [])
    guard !ends.isEmpty else { return nil }
    let budget = ConversationBudget(backend: backend)
    let capacity = max(
      0, budget.admissionTokens - backend.conversationPolicy.compaction.headroomTokens)
    var lower = 0
    var upper = ends.count
    while lower < upper {
      try Task.checkCancellation()
      let middle = lower + (upper - lower) / 2
      let request = try summaryRequest(Array(source.prefix(ends[middle])), memory: memory)
      if try budget.canMeasure(request), try await budget.requiredTokens(request) <= capacity {
        lower = middle + 1
      } else {
        upper = middle
      }
    }
    guard lower > 0 else { return nil }
    let batch = Array(source.prefix(ends[lower - 1]))
    let result = try await backend.generate(summaryRequest(batch, memory: memory), format: .text)
    try Task.checkCancellation()
    guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw TextModelError.invalidResponse
    }
    return .init(
      summary: result, throughMessageID: batch.last?.id,
      references: references(batch, memory: memory), openingStatement: memory.openingStatement)
  }

  private func boundedSource(_ messages: [ChatMessage]) throws -> [ChatMessage] {
    let limit = backend.conversationPolicy.history.checkpoint.window
    var source: [ChatMessage] = []
    var bytes = 0
    for message in messages.prefix(limit.messageLimit) {
      let size = try JSONEncoder().encode(message).count
      guard size <= limit.byteLimit - bytes else { break }
      bytes += size
      source.append(message)
    }
    return source
  }

  private func summaryRequest(_ messages: [ChatMessage], memory: ConversationMemory) throws
    -> TextGenerationRequest
  {
    try ConversationSummaryPrompt.request(
      messages: messages, memory: memory,
      maximumWords: backend.conversationPolicy.compaction.summaryWords,
      maximumTokens: backend.generationProfile.summary.outputTokens)
  }

  private func references(_ messages: [ChatMessage], memory: ConversationMemory)
    -> [ConversationMemory.Reference]
  {
    var result = memory.references
    for source in messages.flatMap(\.sources) {
      result.removeAll { $0.id == source.id }
      result.append(.init(id: source.id, title: source.title))
    }
    return Array(result.suffix(ConversationMemory.maximumReferences))
  }
}
