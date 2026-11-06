import Foundation
import SilliesCore
import SilliesTextModels
import Synchronization

@testable import SilliesReasoning
@testable import SilliesVault

struct NativeRepresentationObservation: Encodable {
  let variant: String
  let caseID: String
  let question: String
  let expected: String
  let request: TextGenerationRequest
  let inputTokens: Int
  let answer: String
  let firstTextSeconds: Double?
  let seconds: Double
  let failure: String?
  let exchanges: [ConversationToolExchange]
  let memories: [CompanionMemory]
}

/// Each case owns fresh persisted state; only the actual app tools can change that state.
struct NativeRepresentationProbe {
  let variant: NativeRepresentationVariant
  let backend: AppleReasoningBackend
  let vault: VaultLibrary
  let conversations: ConversationLibrary
  private static let recordID = UUID(uuidString: "606D370D-D1BA-4739-91DC-2CC72BE70D60")!

  func prepare() async throws {
    var record = SessionRecord(
      kind: .stash,
      origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Notes")),
      metadata: .init(id: Self.recordID, createdAt: Date(timeIntervalSince1970: 1_700_000_000)))
    record.stashedItems = ["The Cedar demo is scheduled for Friday at 09:15."]
    _ = try await vault.commit(.init(records: [.insert(record)]))
  }

  func observe(_ item: NativeRepresentationCase) async throws -> NativeRepresentationObservation {
    let context = try await context(for: item)
    guard let handle = context.historyHandle else { throw ConversationStorageError.invalidData }
    let toolbox = try toolbox(for: context)
    try await toolbox.configure(
      evidence: nil, maximumCalls: backend.conversationPolicy.tools.maximumCalls)
    await toolbox.includeSelectedSources(context.background.records.compactMap(\.source))
    let request = try variant.request(for: context, tools: toolbox.definitions)
    let inputTokens = try await backend.inputTokenCount(request)
    guard try await ConversationBudget(backend: backend).admits(request) else {
      throw TextModelError.contextLimit
    }
    let started = ContinuousClock.now
    let firstText = Mutex<Double?>(nil)
    var answer = ""
    var failure: String?
    do {
      answer = try await backend.streamConversation(request, tools: toolbox) { text in
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        firstText.withLock { if $0 == nil { $0 = Self.seconds(since: started) } }
      }
    } catch { failure = String(reflecting: error) }
    let elapsed = Self.seconds(since: started)
    let memories = try await conversations.memories(
      .init(handle: handle, text: "", limit: 200))
    return await NativeRepresentationObservation(
      variant: variant.rawValue, caseID: item.id, question: item.prompt, expected: item.expected,
      request: request, inputTokens: inputTokens, answer: answer,
      firstTextSeconds: firstText.withLock { $0 }, seconds: elapsed, failure: failure,
      exchanges: toolbox.exchanges, memories: memories)
  }

  private func context(for item: NativeRepresentationCase) async throws -> ChatContext {
    let opened = try await conversations.open(.init(id: item.id, name: "Pogo"))
    let message = ChatMessage(role: .user, text: item.prompt)
    try await conversations.save(
      .init(handle: opened.handle, messages: [message], checkpoint: .init(), savedAt: Date()))
    let context = ChatContext(
      companionName: "Pogo", profile: .init(personality: "Friendly and concise"),
      messages: [message]
    ).inHistory(opened.handle)
    var selected = ConversationRecordSelection()
    switch item.evidence {
    case .none: break
    case .selected: try selected.add(Self.recordID)
    case .pinned: try await pinHumanName(opened.handle)
    case .selectedAndPinned:
      try selected.add(Self.recordID)
      try await pinHumanName(opened.handle)
    }
    return try await ConversationBackgroundAccess(materials: vault, personalFacts: conversations)
      .prepare(context.selecting(selected))
  }

  private func pinHumanName(_ handle: ConversationHandle) async throws {
    _ = try await conversations.savePersonalFact(
      .init(handle: handle, scope: .companion, fact: .init(key: "preferred name", value: "Mira")))
  }

  private func toolbox(for context: ChatContext) throws -> ConversationToolbox {
    try ConversationToolbox(
      tools: [
        VaultSearchTool(library: vault), VaultReadTool(library: vault),
        ConversationClarificationTool(),
      ]
        + ConversationHistoryTools(conversations: conversations, memories: conversations).tools(
          for: context), progress: { _ in })
  }

  private static func seconds(since start: ContinuousClock.Instant) -> Double {
    let value = start.duration(to: .now).components
    return Double(value.seconds) + Double(value.attoseconds) / 1e18
  }
}
