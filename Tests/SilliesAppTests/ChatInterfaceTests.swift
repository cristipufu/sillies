import AppKit
import QuartzCore
import SilliesChat
import SilliesCore
import SilliesReasoning
import SwiftUI
import Testing

@testable import SilliesApp

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
  func reply(to context: ChatContext) async throws -> String {
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
  session.draft = "My next thought is still editable."
  try renderSkillInterface(
    ChatSessionView(model: session, openSettings: { _ in }), size: ChatWindowLayout.minimumSize,
    name: "sillies-chat-failure")
  session.finish {}
}

private struct FailedChatReply: ConversationResponding {
  func reply(to context: ChatContext) async throws -> String {
    throw SessionFailure(
      category: .unknown, message: String(repeating: "A long runtime diagnostic. ", count: 100))
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
