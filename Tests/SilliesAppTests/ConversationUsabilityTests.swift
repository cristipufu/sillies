import AppKit
import SilliesChat
import SilliesCore
import SilliesReasoning
import SilliesVault
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func conversationIdeasPreserveDraftsAndClarificationsResolveOnlyOnce() async throws
{
  let reply = UsabilityReply()
  let session = ChatWindowFixture.makeReadySession(conversation: reply)
  defer { session.finish {} }
  #expect(session.useSuggestedDraft("Discuss my recording."))
  #expect(!session.useSuggestedDraft("Overwrite my draft."))
  session.send()
  try await usabilityWait { session.pendingClarification != nil && session.canCompose }
  let question = try #require(session.pendingClarification)
  session.draft = "A thought I haven’t sent yet"
  session.answerClarification(UUID(), choice: question.choices[0])
  #expect(session.pendingClarification == question)
  session.answerClarification(question.id, choice: question.choices[0])
  session.answerClarification(question.id, choice: question.choices[0])
  try await usabilityWait { session.canCompose }
  #expect(session.draft == "A thought I haven’t sent yet")
  #expect(session.messages.filter { $0.role == .user && $0.text == question.choices[0] }.count == 1)
  #expect(
    session.messages.first(where: { $0.clarification?.id == question.id })?.clarification?
      .resolution == .answered)
  #expect(session.pendingClarification == nil)
}

@Test @MainActor func pendingQuestionSurvivesReopeningAndDismissalDoesNotInvokeTheModel()
  async throws
{
  let reply = UsabilityReply()
  let session = ChatWindowFixture.makeReadySession(conversation: reply)
  defer { session.finish {} }
  let question = try #require(
    ChatClarification(question: "Which meeting?", choices: ["Planning", "Review"]))
  let stored = ChatMessage(role: .companion, text: question.question).asking(question)
  let decoded = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(stored))
  session.restore(
    .init(
      handle: .init(companionID: "mochi", generation: UUID()),
      checkpoint: .init(draft: "Kept draft"),
      page: .init(
        entries: [.init(sequence: 1, message: decoded, createdAt: Date())], hasOlder: false,
        hasNewer: false)))
  #expect(session.pendingClarification == question)
  session.dismissClarification(question.id)
  #expect(session.pendingClarification == nil)
  #expect(session.messages.last?.clarification?.resolution == .cancelled)
  #expect(session.draft == "Kept draft")
  #expect(await reply.calls == 0)
  session.restore(
    .init(
      handle: .init(companionID: "mochi", generation: UUID()), checkpoint: .init(),
      page: .init(
        entries: [.init(sequence: 1, message: decoded, createdAt: Date())],
        hasOlder: false, hasNewer: false)))
  #expect(session.useSuggestedDraft("Let's discuss a recording."))
  #expect(session.messages.last?.clarification?.resolution == .superseded)
  #expect(session.pendingClarification == nil)
  #expect(await reply.calls == 0)
}

@Test @MainActor func conversationSearchRejectsLateResultsAndNavigationDoesNotReplaceTheDraft()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let store = ConversationLibrary(directory: directory)
  let delayed = DelayedUsabilitySearch(store: store)
  let session = ChatWindowFixture.makeReadySession(
    conversation: UsabilityReply(), history: .stored(conversations: delayed, memories: store),
    owner: .init(id: "pogo", name: "Pogo"))
  await session.restoreHistory()
  let first = ChatMessage(role: .user, text: "quartz")
  let second = ChatMessage(role: .user, text: "marigold")
  session.history.stage(first)
  session.history.stage(second)
  session.draft = "Unsent thought"
  let slow = Task { await session.browser.search("quartz") }
  try await usabilityWait { await delayed.isWaiting }
  await session.browser.search("marigold")
  #expect(session.browser.matches.map(\.id) == [second.id])
  await delayed.release()
  await slow.value
  #expect(session.browser.matches.map(\.id) == [second.id])
  #expect(!session.browser.isSearching)
  #expect(await session.browser.show(.around(first.id)))
  #expect(session.draft == "Unsent thought")
  #expect(session.browser.focusedMessageID == first.id)
  await session.browser.search("cancelled")
  #expect(session.browser.failure == nil && !session.browser.isSearching)
  await delayed.cancelNextPage()
  #expect(!(await session.browser.show(.latest)))
  #expect(session.browser.failure == nil && !session.browser.isLoading)
  session.browser.cancelSearch()
  #expect(session.browser.matches.isEmpty)
  await withCheckedContinuation { continuation in session.finish { continuation.resume() } }
}

@Test @MainActor func conversationReadingSizesPreserveNativeSelectionAndInputComposition() {
  let message = ChatMessageTextView()
  message.string = "A café, a plan, and a thought."
  let range = NSRange(location: 2, length: 4)
  message.setSelectedRange(range)
  ChatTypography.apply(.large, to: message)
  #expect(message.font?.pointSize == ChatReadingSize.large.points)
  #expect(message.selectedRange() == range)
  let editor = ChatComposerTextView()
  editor.string = "A draft"
  editor.font = ChatTypography.messageFont
  editor.setMarkedText(
    "你", selectedRange: NSRange(location: 1, length: 0),
    replacementRange: NSRange(location: NSNotFound, length: 0))
  let composing = editor.string
  ChatTypography.apply(.large, to: editor)
  #expect(editor.hasMarkedText() && editor.string == composing)
  #expect(editor.font?.pointSize == ChatTypography.messageSize)
  editor.unmarkText()
  ChatTypography.apply(.large, to: editor)
  #expect(editor.font?.pointSize == ChatReadingSize.large.points)
}

@Test @MainActor func conversationReadingPreferenceSurvivesRelaunchAndRejectsInvalidValues() throws
{
  let suite = "sillies-reading-test-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let preferences = ChatReadingPreferences(defaults: defaults)
  #expect(preferences.size == .standard)
  preferences.size = .large
  #expect(ChatReadingPreferences(defaults: defaults).size == .large)
  defaults.set("unknown", forKey: "chatMessageSize")
  #expect(ChatReadingPreferences(defaults: defaults).size == .standard)
}

@Test @MainActor func conversationReadingSizePreservesComposerInk() throws {
  let editor = ChatComposerTextView()
  editor.font = ChatTypography.messageFont
  editor.textColor = .systemOrange
  ChatTypography.apply(.large, to: editor)
  editor.insertText("A new thought", replacementRange: NSRange(location: 0, length: 0))
  let color = try #require(
    editor.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
  #expect(color == .systemOrange)
  #expect(editor.font?.pointSize == ChatReadingSize.large.points)
}

@Test @MainActor func conversationUsabilityFitsMinimumSizeInBothThemes() async throws {
  let session = ChatWindowFixture.makeReadySession(
    conversation: UsabilityReply(), history: .transient, owner: .init(id: "pogo", name: "Pogo"))
  defer { session.finish {} }
  for scheme in [ColorScheme.light, .dark] {
    try renderSkillInterface(
      ConversationBubbleView(
        presentation: ConversationBubblePresentation(),
        content: ChatSessionView(
          model: session, openSettings: { _ in }, close: {}, renderer: "frog", motion: .reduced)
      )
      .environment(\.colorScheme, scheme), size: ChatWindowLayout.minimumSize,
      name: "sillies-conversation-starters-\(scheme)")
  }
  session.draft = "Can we discuss that meeting?"
  session.send()
  try await usabilityWait { session.pendingClarification != nil && session.canCompose }
  for scheme in [ColorScheme.light, .dark] {
    try renderSkillInterface(
      ConversationBubbleView(
        presentation: ConversationBubblePresentation(),
        content: ChatSessionView(
          model: session, openSettings: { _ in }, close: {}, renderer: "frog", motion: .reduced)
      )
      .environment(\.colorScheme, scheme), size: ChatWindowLayout.initialSize,
      name: "sillies-conversation-clarification-\(scheme)")
    try renderSkillInterface(
      ConversationSearchView(browser: session.browser).environment(\.colorScheme, scheme),
      size: CGSize(width: 400, height: 460), name: "sillies-conversation-search-\(scheme)")
  }
}

@Test @MainActor func conversationUsabilityFitsLargeTextAndPreservesStoppedReplies() throws {
  let session = ChatWindowFixture.makeReadySession(
    conversation: UsabilityReply(), history: .transient,
    owner: .init(id: "pogo", name: "Pogo — un compagnon pour les longues journées"))
  defer { session.finish {} }
  let question = try #require(
    ChatClarification(
      question: "De quelle réunion souhaitez-vous parler ?",
      choices: [
        "La réunion de planification du lundi avec l’équipe de développement et les responsables du projet",
        "La revue du vendredi sur les retours des utilisateurs et les prochaines améliorations de l’application",
        "Une autre réunion enregistrée dans mes Archives",
      ]))
  let user = ChatMessage(role: .user, text: "Parlons de notre dernière réunion.")
  let response = ChatMessage(
    role: .companion,
    text: "J’ai trouvé deux enregistrements qui pourraient correspondre.\n\n" + question.question
  ).asking(question)
  let stopped = ChatMessage(role: .companion, text: "Let’s start with the decisions we made.")
    .withDelivery(.interrupted, spokenText: nil)
  for (name, message) in [("large-choices", response), ("stopped", stopped)] {
    session.restore(
      .init(
        handle: .init(companionID: "pogo", generation: UUID()), checkpoint: .init(),
        page: .init(
          entries: [
            .init(sequence: 1, message: user, createdAt: .distantPast),
            .init(sequence: 2, message: message, createdAt: .distantPast),
          ], hasOlder: false, hasNewer: false)))
    session.draft = "An unsent thought stays here."
    for scheme in [ColorScheme.light, .dark] {
      try renderSkillInterface(
        ConversationBubbleView(
          presentation: ConversationBubblePresentation(),
          content: ChatSessionView(
            model: session, openSettings: { _ in }, close: {}, renderer: "frog", motion: .reduced,
            readingPreference: .constant(.large))
        ).environment(\.colorScheme, scheme), size: ChatWindowLayout.minimumSize,
        name: "sillies-conversation-\(name)-\(scheme)")
    }
  }
  #expect(session.canRetry && session.failure == nil)
  #expect(session.draft == "An unsent thought stays here.")
}

@Test @MainActor func conversationUsabilityKeepsSelectedTextWhenChoicesArrive() async throws {
  let session = ChatWindowFixture.makeReadySession(conversation: UsabilityReply())
  let handle = ConversationHandle(companionID: "mochi", generation: UUID())
  let message = ChatMessage(role: .companion, text: "I found two meetings.")
  func restore(_ message: ChatMessage) {
    session.restore(
      .init(
        handle: handle, checkpoint: .init(),
        page: .init(
          entries: [.init(sequence: 1, message: message, createdAt: .distantPast)],
          hasOlder: false, hasNewer: false)))
  }
  restore(message)
  let window = NSWindow(
    contentRect: CGRect(origin: .zero, size: ChatWindowLayout.initialSize),
    styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  defer {
    window.close()
    session.finish {}
  }
  let content = NSHostingView(rootView: ChatMessagesView(model: session, motion: .reduced))
  window.contentView = content
  content.frame = CGRect(origin: .zero, size: ChatWindowLayout.initialSize)
  func messageView(in view: NSView) -> NSTextView? {
    if let text = view as? NSTextView, text.string.hasPrefix(message.text) { return text }
    return view.subviews.lazy.compactMap { messageView(in: $0) }.first
  }
  try await usabilityWait {
    content.layoutSubtreeIfNeeded()
    return messageView(in: content) != nil
  }
  let original = try #require(messageView(in: content))
  let selection = NSRange(location: 0, length: 7)
  original.setSelectedRange(selection)
  let question = try #require(
    ChatClarification(question: "Which one?", choices: ["Planning", "Review"]))
  restore(message.withText(message.text + "\n" + question.question).asking(question))
  try await usabilityWait {
    content.layoutSubtreeIfNeeded()
    return messageView(in: content)?.string.contains(question.question) == true
  }
  #expect(messageView(in: content) === original)
  #expect(original.selectedRange() == selection)
  #expect(!window.isVisible)
}

private actor UsabilityReply: ConversationResponding {
  private(set) var calls = 0
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    -> ChatReply
  {
    calls += 1
    if calls == 1 {
      return ChatReply(text: "Which meeting would you like to discuss?").asking(
        .init(
          question: "Which meeting would you like to discuss?",
          choices: ["Monday’s planning session", "Friday’s project review"]))
    }
    return .init(text: "Let’s look at that meeting together.")
  }
}

private actor DelayedUsabilitySearch: ConversationRepository {
  let store: ConversationLibrary
  private var waiting: CheckedContinuation<Void, Never>?
  private var cancelsPage = false
  var isWaiting: Bool { waiting != nil }
  init(store: ConversationLibrary) { self.store = store }
  func cancelNextPage() { cancelsPage = true }
  func release() {
    waiting?.resume()
    waiting = nil
  }
  func search(_ request: ConversationSearchRequest) async throws -> [ConversationSearchMatch] {
    if request.query == "cancelled" { throw CancellationError() }
    if request.query == "quartz" { await withCheckedContinuation { waiting = $0 } }
    return try await store.search(request)
  }
  func open(_ owner: ConversationOwner) async throws -> ConversationSnapshot {
    try await store.open(owner)
  }
  func save(_ update: ConversationUpdate) async throws { try await store.save(update) }
  func page(_ request: ConversationPageRequest) async throws -> ConversationPage {
    if cancelsPage {
      cancelsPage = false
      throw CancellationError()
    }
    return try await store.page(request)
  }
  func checkpoint(_ handle: ConversationHandle) async throws -> ConversationMemorySnapshot {
    try await store.checkpoint(handle)
  }
  func advanceCheckpoint(_ update: ConversationMemoryUpdate) async throws -> Bool {
    try await store.advanceCheckpoint(update)
  }
  func conversations() async throws -> [ConversationHeader] { try await store.conversations() }
  func clear(_ handle: ConversationHandle) async throws -> ConversationSnapshot {
    try await store.clear(handle)
  }
}

@MainActor private func usabilityWait(_ condition: () async -> Bool) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: .seconds(2))
  while !(await condition()), clock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
  #expect(await condition())
}
