import Foundation
import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning
@testable import SilliesVault

struct ConversationContinuityFixture {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  var library: ConversationLibrary { ConversationLibrary(directory: directory) }
  func remove() {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }
  func seed(_ count: Int, in store: ConversationLibrary) async throws -> ConversationHandle {
    let opened = try await store.open(.init(id: "pogo", name: "Pogo"))
    let batchSize = 200
    for start in stride(from: 0, to: count, by: batchSize) {
      let messages = (start..<min(count, start + batchSize)).map {
        ChatMessage(
          role: $0.isMultiple(of: 2) ? .user : .companion, text: "Archived discussion \($0).")
      }
      try await store.save(
        .init(
          handle: opened.handle, messages: messages, checkpoint: .init(), savedAt: .now))
    }
    return opened.handle
  }
  func question(
    _ text: String, handle: ConversationHandle, store: ConversationLibrary,
    session: UUID = UUID()
  ) async throws -> ChatContext {
    let current = ChatMessage(role: .user, text: text)
    try await store.save(
      .init(
        handle: handle, messages: [current], checkpoint: .init(), savedAt: .now))
    return .init(companionName: "Pogo", profile: .init(personality: "Curious"), messages: [current])
      .inTurn(UUID(), session: session).inHistory(handle)
  }
}

actor ContinuityBackend: ConversationBackend {
  enum SummaryBehavior { case immediate, waiting, failed }
  nonisolated let contextWindowTokens = 4_096
  nonisolated var conversationPolicy: ConversationPolicy { AppleConversationPolicy.conversation }
  nonisolated var generationProfile: TextGenerationProfile { AppleConversationPolicy.generation }
  private let behavior: SummaryBehavior
  private(set) var summaryCalls = 0
  private(set) var cancelledSummaries = 0
  private(set) var measuredMessages = 0
  private(set) var measurements = 0
  private(set) var lastRequest: TextGenerationRequest?
  let started = AsyncStream<Void>.makeStream()
  let cancelled = AsyncStream<Void>.makeStream()
  init(_ behavior: SummaryBehavior = .immediate) { self.behavior = behavior }
  func availabilityNotice(localeIdentifier: String?) -> String? { nil }
  func inputTokenCount(_ request: TextGenerationRequest) throws -> Int {
    measurements += 1
    measuredMessages = max(measuredMessages, request.messages.count)
    return try ConversationTokenEstimate.count(request)
  }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) async throws -> String {
    summaryCalls += 1
    started.continuation.yield(())
    switch behavior {
    case .failed: throw TextModelError.invalidResponse
    case .waiting:
      do { try await Task.sleep(for: .seconds(30)) } catch {
        cancelledSummaries += 1
        cancelled.continuation.yield(())
        throw error
      }
    case .immediate: break
    }
    return "Earlier discussion has been checkpointed."
  }
  func converse(_ request: TextGenerationRequest, tools: ConversationToolbox) -> String {
    lastRequest = request
    return "Ready to continue."
  }
}

actor ConversationReadProbe: ConversationRepository {
  let base: ConversationLibrary
  private(set) var pageReads = 0
  private(set) var checkpointReads = 0
  private(set) var maximumPageMessages = 0
  private(set) var maximumPageBytes = 0
  init(_ base: ConversationLibrary) { self.base = base }
  func open(_ owner: ConversationOwner) async throws -> ConversationSnapshot {
    try await base.open(owner)
  }
  func save(_ update: ConversationUpdate) async throws { try await base.save(update) }
  func checkpoint(_ handle: ConversationHandle) async throws -> ConversationMemorySnapshot {
    checkpointReads += 1
    return try await base.checkpoint(handle)
  }
  func advanceCheckpoint(_ update: ConversationMemoryUpdate) async throws -> Bool {
    try await base.advanceCheckpoint(update)
  }
  func page(_ request: ConversationPageRequest) async throws -> ConversationPage {
    pageReads += 1
    let result = try await base.page(request)
    maximumPageMessages = max(maximumPageMessages, result.entries.count)
    maximumPageBytes = max(
      maximumPageBytes, try JSONEncoder().encode(result.entries.map(\.message)).count)
    return result
  }
  func search(_ request: ConversationSearchRequest) async throws -> [ConversationSearchMatch] {
    try await base.search(request)
  }
  func conversations() async throws -> [ConversationHeader] { try await base.conversations() }
  func clear(_ handle: ConversationHandle) async throws -> ConversationSnapshot {
    try await base.clear(handle)
  }
}
