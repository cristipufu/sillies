import AppKit
import QuartzCore
import SilliesChat
import SilliesCore
import SilliesReasoning
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func emptyAndShortSavedChatsFitWithoutHistoryNavigation() throws {
  let session = ChatWindowFixture.makeReadySession(conversation: MissingChatModel())
  defer { session.finish {} }
  let handle = ConversationHandle(companionID: "mochi", generation: UUID())
  let entries: [ConversationEntry] = [
    .init(sequence: 1, message: .init(role: .user, text: "Hello!"), createdAt: .distantPast),
    .init(
      sequence: 2, message: .init(role: .companion, text: "Hello! How's your day going?"),
      createdAt: .distantPast),
  ]
  for page in [
    ConversationPage(entries: [], hasOlder: false, hasNewer: false),
    .init(entries: entries, hasOlder: false, hasNewer: false),
  ] {
    session.restore(.init(handle: handle, checkpoint: .init(), page: page))
    let navigation = ConversationNavigation(
      latestMessageID: session.messages.last?.id, hasEarlierMessages: session.hasEarlierMessages,
      page: session.browser.page, nearBottom: true)
    #expect(!navigation.showsEarlier && !navigation.showsLatest)
    try renderSkillInterface(
      ConversationBubbleView(
        presentation: ConversationBubblePresentation(),
        content: ChatSessionView(
          model: session, openSettings: { _ in }, renderer: "cat", motion: .reduced)
      ).environment(\.colorScheme, .light),
      size: ChatWindowLayout.initialSize,
      name: "sillies-chat-navigation-\(page.entries.isEmpty ? "empty" : "short")")
  }
}

@Test @MainActor func chatExplainsMissingTextModelsBeforeTheFirstMessage() async throws {
  let session = ChatWindowFixture.makeReadySession(conversation: MissingChatModel())
  await session.refreshAvailability()
  #expect(session.notice?.settingsDestination == .textModels)
  #expect(session.canCompose)
  #expect(session.messages.isEmpty)
  try renderSkillInterface(
    ChatSessionView(model: session, openSettings: { _ in }), size: ChatWindowLayout.minimumSize,
    name: "sillies-chat-model-setup")
  session.finish {}
}

private struct MissingChatModel: ConversationResponding {
  func availabilityNotice(localeIdentifier: String?) async -> String? {
    "Choose Apple Intelligence or download a text model in Local AI to start chatting."
  }
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  {
    throw SessionFailure(category: .unknown, message: "A text model is needed for replies.")
  }
}

@Test @MainActor func chatFailureKeepsTheConversationAndComposerVisible() async throws {
  let session = ChatWindowFixture.makeSession(conversation: FailedChatReply())
  for _ in 0..<100 {
    if session.failure != nil { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(session.failure != nil)
  #expect(session.messages.count == 1)
  #expect(session.recoverySettingsDestination == .textModels)
  #expect(session.canRetry)
  session.draft = "My next thought is still editable."
  try renderSkillInterface(
    ChatSessionView(model: session, openSettings: { _ in }), size: ChatWindowLayout.minimumSize,
    name: "sillies-chat-failure")
  session.finish {}
}

private struct FailedChatReply: ConversationResponding {
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  {
    throw SessionFailure(
      category: .textGeneration,
      message: String(repeating: "A long runtime diagnostic. ", count: 100))
  }
}

@Test @MainActor func voiceSettingsUseTheSharedSettingsLayout() async throws {
  let suite = "sillies-voice-ui-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let services = try VoiceServices(defaults: defaults, directory: directory)
  #expect(await services.speech.availabilityNotice(language: "en") != nil)
  await services.models.load()
  #expect(services.models.manifests.count == 5)
  #expect(services.models.error == nil)
  try renderSkillInterface(
    ScrollView { VoiceModelSettingsView(model: services.models).padding(20) }.background(
      SilliesTheme().card),
    size: CGSize(width: 520, height: 600), name: "sillies-voice-settings")
  await services.environment.stop()
}

@Test @MainActor func chatInterfaceKeepsTranscriptAndComposerInsideMinimumWindow() async throws {
  let session = ChatWindowFixture.makeSession()
  for _ in 0..<100 {
    if session.phase == .ready { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(session.messages.count == 2)
  let controller = ChatSessionWindowController(appearance: ThemeEnvironment())
  controller.show(session, openSettings: { _ in }, renderer: "cat")
  let window = try #require(controller.window)
  defer { controller.close() }
  window.setContentSize(ChatWindowLayout.minimumSize)
  try DisplayFrameSequence.presentCreatedWindows()
  let content = try #require(window.contentView)
  content.layoutSubtreeIfNeeded()
  func messageTexts(in view: NSView) -> [String] {
    if let text = view as? NSTextView { return [text.string] }
    return view.subviews.flatMap { messageTexts(in: $0) }
  }
  let rendered = messageTexts(in: content)
  for message in session.messages { #expect(rendered.contains(message.text)) }
  try renderSkillInterface(
    ChatSessionView(model: session, openSettings: { _ in }, renderer: "cat"),
    size: ChatWindowLayout.minimumSize,
    name: "sillies-chat-minimum")
  try renderSkillInterface(
    ChatSessionView(model: session, openSettings: { _ in }, renderer: "cat").environment(
      \.colorScheme, .light),
    size: ChatWindowLayout.initialSize, name: "sillies-chat-light")
  session.draft = String(repeating: "A longer thought with punctuation. ", count: 80)
  try renderSkillInterface(
    ChatSessionView(model: session, openSettings: { _ in }), size: ChatWindowLayout.minimumSize,
    name: "sillies-chat-long-draft")
  session.finish {}
}

@Test @MainActor func speechArtworkReturnsToRestAfterInvalidLevelsAndInterruption() {
  let head = CALayer()
  let mouth = CAShapeLayer()
  mouth.path = CGPath(ellipseIn: CGRect(x: 10, y: 10, width: 8, height: 4), transform: nil)
  mouth.strokeColor = NSColor.black.cgColor
  head.addSublayer(mouth)
  let animation = CharacterSpeechAnimation(head: head)
  animation.registerMouth(mouth)
  animation.update(level: 0.6)
  #expect(mouth.opacity == 0)
  #expect(head.animation(forKey: "speech.nod")?.isRemovedOnCompletion == false)
  animation.update(level: .nan)
  #expect(mouth.opacity == 1)
  #expect((head.animation(forKey: "speech.nod") as? CABasicAnimation)?.toValue as? Double == 0)
}

@Test @MainActor func chatRapidCloseAndReopenDoesNotLeaveAnInvisibleWindow() async throws {
  let session = ChatWindowFixture.makeSession()
  let controller = ChatSessionWindowController(appearance: ThemeEnvironment())
  controller.show(session, openSettings: { _ in }, renderer: "cat")
  let window = try #require(controller.window)
  defer {
    controller.close()
    session.finish {}
  }
  window.performClose(nil)
  controller.show(session, openSettings: { _ in }, renderer: "cat")
  try DisplayFrameSequence.run(count: 30) { _ in }
  #expect(window.isVisible)
  #expect(window.alphaValue == 1)
  window.performClose(nil)
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while window.isVisible, ContinuousClock.now < deadline {
    try DisplayFrameSequence.presentCreatedWindows()
    await Task.yield()
  }
  #expect(!window.isVisible)
  #expect(session.phase != .finished)
}

private struct VaultCardReply: ConversationResponding {
  let sources: [ChatSource]
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  {
    .init(text: "Here are the saved items I found.", sources: sources)
  }
}

@Test @MainActor func chatVaultResultsFitTheSharedChatWindow() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let store = SessionVaultStore(directory: directory)
  let sources = (0..<3).map { index in
    ChatSource(
      header: .init(
        SessionRecord(
          kind: index == 0 ? .snap : .stash,
          origin: .init(
            characterID: "pogo", characterName: "Pogo",
            source: .init(appName: index == 0 ? "Ghostty terminal" : "Aurora project")))),
      excerpt: "A saved project item with searchable text and a link to its original record.",
      links: index == 0 ? [] : [URL(string: "https://example.com/project-aurora")!])
  }
  let session = ChatWindowFixture.makeSession(conversation: VaultCardReply(sources: sources))
  for _ in 0..<100 {
    if session.phase == .ready { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(session.messages.last?.sources == sources)
  let presentation = ChatVaultPresentation(store: store, openRecord: { _ in })
  for scheme in [ColorScheme.light, .dark] {
    try renderSkillInterface(
      ChatSessionView(model: session, openSettings: { _ in }, motion: .reduced, vault: presentation)
        .environment(\.colorScheme, scheme),
      size: ChatWindowLayout.minimumSize, name: "sillies-chat-vault-\(scheme)")
  }
  session.finish {}
}

@Test @MainActor func chatSaveDeliversTheFullTranscriptDuringModalTermination() async throws {
  let session = ChatWindowFixture.makeSession()
  for _ in 0..<100 {
    if session.phase == .ready { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  let expected = session.transcript
  let skill = ConversationActivity(presentation: session)
  var completed = false
  skill.finish(
    .init(now: 10, startedAt: 0, companionID: "mochi", companionName: "Mochi", target: nil)
  ) {
    #expect($0 == nil)
    completed = true
  }
  pumpChatTermination { completed }
  #expect(completed)
  #expect(session.transcript == expected)
}

@MainActor private func pumpChatTermination(_ finished: () -> Bool) {
  let deadline = ContinuousClock.now.advanced(by: .seconds(3))
  while !finished(), ContinuousClock.now < deadline {
    CFRunLoopRunInMode(CFRunLoopMode(RunLoop.Mode.modalPanel.rawValue as CFString), 0.01, true)
  }
}

@Test @MainActor func streamedMessageUpdatesPreserveSelectionAcrossUnicodeBoundaries() {
  let view = NSTextView()
  let coordinator = ChatMessageText.Coordinator { _ in }
  view.string = "Read this 👋 carefully"
  view.setSelectedRange(NSRange(location: 0, length: 9))
  for text in [
    "Read this 👋 carefully. More text", "Read this 👋🏽 carefully. More text",
    "Read this 🙂 carefully.", "Read",
  ] {
    coordinator.replaceText(in: view, with: text)
    #expect(view.string == text)
    #expect(view.selectedRange() == NSRange(location: 0, length: min(9, (text as NSString).length)))
  }
}

private actor StreamingInterfaceReply: ConversationResponding {
  var continuation: CheckedContinuation<Void, Never>?
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  {
    try await streamReply(to: context, progress: progress, receive: { _ in })
  }
  func streamReply(
    to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void,
    receive: @escaping ConversationTextSink
  ) async throws -> ChatReply {
    try await receive("Read this first. ")
    await withCheckedContinuation { continuation = $0 }
    try await receive("Then the new words arrive. ")
    await withCheckedContinuation { continuation = $0 }
    return .init(text: "Read this first. Then the new words arrive.")
  }
  func advance() {
    continuation?.resume()
    continuation = nil
  }
}

@Test @MainActor func chatStreamingBubbleUpdatesWithoutReplacingHistoryOrLosingSelection()
  async throws
{
  let reply = StreamingInterfaceReply()
  let session = ChatWindowFixture.makeSession(conversation: reply)
  let controller = ChatSessionWindowController(appearance: ThemeEnvironment())
  controller.show(session, openSettings: { _ in }, renderer: "cat")
  let content = try #require(controller.window?.contentView)
  defer {
    controller.close()
    session.finish {}
  }
  func messageView(in view: NSView) -> NSTextView? {
    if let text = view as? NSTextView, text.string.hasPrefix("Read this") { return text }
    return view.subviews.lazy.compactMap { messageView(in: $0) }.first
  }
  for _ in 0..<100 {
    try DisplayFrameSequence.presentCreatedWindows()
    if messageView(in: content) != nil, await reply.continuation != nil { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  let first = try #require(messageView(in: content))
  first.setSelectedRange(NSRange(location: 0, length: 9))
  let placeholder = try #require(session.messages.last)
  await reply.advance()
  for _ in 0..<100 {
    try DisplayFrameSequence.presentCreatedWindows()
    if first.string.contains("new words"), await reply.continuation != nil { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(session.messages.last == placeholder)
  #expect(first.string == "Read this first. Then the new words arrive. ")
  #expect(first.selectedRange() == NSRange(location: 0, length: 9))
  await reply.advance()
  for _ in 0..<100 {
    if session.phase == .ready { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(session.phase == .ready)
}

@Test @MainActor func latestActionClearsSelectionOnceThenAllowsNewSelections() {
  let view = NSTextView()
  let coordinator = ChatMessageText.Coordinator { _ in }
  view.string = "Earlier words and new words."
  view.setSelectedRange(NSRange(location: 0, length: 7))
  coordinator.resetSelection(in: view, revision: nil)
  #expect(view.selectedRange().length == 7)
  let latestAction = UUID()
  coordinator.resetSelection(in: view, revision: latestAction)
  #expect(view.selectedRange().length == 0)
  view.setSelectedRange(NSRange(location: 0, length: 7))
  coordinator.replaceText(in: view, with: "Earlier words and new words. Another batch.")
  coordinator.resetSelection(in: view, revision: latestAction)
  #expect(view.selectedRange().length == 7)
}

@Test @MainActor func chatSizingDoesNotRelayoutTheDisplayedTextForSpeculativeWidths() throws {
  let view = NSTextView(frame: CGRect(x: 0, y: 0, width: 300, height: 160))
  view.font = .systemFont(ofSize: 15)
  view.textContainerInset = .zero
  let container = try #require(view.textContainer)
  container.lineFragmentPadding = 0
  container.containerSize = CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
  view.string =
    "Readable words should stay in the same place while SwiftUI asks about other widths."
  let layout = try #require(view.layoutManager)
  layout.ensureLayout(for: container)
  let displayed = layout.usedRect(for: container)
  let size = container.containerSize
  let measurement = ChatMessageLayout()
  let narrow = try #require(measurement.size(of: view.attributedString(), width: 60))
  let wide = try #require(measurement.size(of: view.attributedString(), width: 300))
  #expect(narrow.height > wide.height)
  layout.ensureLayout(for: container)
  #expect(container.containerSize == size)
  #expect(layout.usedRect(for: container) == displayed)
}

@Test @MainActor func chatMessageTextKeepsItsMeasuredHeightWhileStreamingWithoutFocus() throws {
  let view = ChatMessageTextView()
  let coordinator = ChatMessageText.Coordinator { _ in }
  let passages = [
    "A small thought.", String(repeating: "A longer reply with readable line spacing. ", count: 18),
    "One paragraph.\n\nȘtefan says hello 👋🏽. 日本語 العربية.\nOne more paragraph.",
  ]
  for text in passages {
    coordinator.replaceText(in: view, with: text)
    for width in [CGFloat(320), 160, 280] {
      let size = try #require(
        coordinator.measurement.size(of: view.attributedString(), width: width))
      view.setFrameSize(size)
      let layout = try #require(view.layoutManager)
      let container = try #require(view.textContainer)
      layout.ensureLayout(for: container)
      #expect(layout.usedRect(for: container).height <= ceil(view.bounds.height))
      #expect(layout.numberOfGlyphs > 0)
      #expect(view.string == text)
      #expect(view.font?.pointSize == ChatTypography.messageSize)
      #expect(view.window == nil)
    }
  }
  #expect(coordinator.measurement.size(of: view.attributedString(), width: .infinity) == nil)
  #expect(coordinator.measurement.size(of: view.attributedString(), width: 0) == nil)
}

@Test @MainActor func chatMessageTypographyFitsTheSharedWindowInBothThemes() async throws {
  let session = ChatWindowFixture.makeSession()
  defer { session.finish {} }
  for _ in 0..<100 {
    if session.phase == .ready { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(session.messages.count == 2)
  for scheme in [ColorScheme.light, .dark] {
    try renderSkillInterface(
      ChatSessionView(model: session, openSettings: { _ in }, renderer: "cat")
        .environment(\.colorScheme, scheme),
      size: ChatWindowLayout.initialSize,
      name: "sillies-chat-typography-\(scheme == .light ? "light" : "dark")")
  }
}

@Test @MainActor func conversationAttachedBubbleFitsBothModesWithoutNativePresentation()
  async throws
{
  let session = ChatWindowFixture.makeSession()
  session.showChat()
  for _ in 0..<100 {
    if session.phase == .ready { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  let presentation = ConversationBubblePresentation()
  for scheme in [ColorScheme.light, .dark] {
    for tail in [ConversationBubbleLayout.Tail.top, .bottom, .left, .right] {
      presentation.tail = tail
      presentation.tailOffset = tail.isSide ? 274 : 200
      let size = tail.isSide ? CGSize(width: 412, height: 548) : ChatWindowLayout.initialSize
      try renderSkillInterface(
        ConversationBubbleView(
          presentation: presentation,
          content: ChatSessionView(model: session, openSettings: { _ in }, renderer: "cat")
        )
        .environment(\.colorScheme, scheme), size: size,
        name: "sillies-continuous-chat-\(scheme)-\(tail)")
    }
  }
  try renderSkillInterface(
    TalkCaptionsView(model: session), size: CGSize(width: 360, height: 120),
    name: "sillies-talk-captions")
  session.finish {}
}
