import AppKit
import SilliesChat
import SilliesCore
import SilliesReasoning
import SilliesVault
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func chatDisabledTextRemainsVisibleUntilItsPageIsConcealed() throws {
  let host = NSHostingController(
    rootView: VStack {
      ChatMessageText(
        text: "A reply remains readable.", color: .labelColor, selectionChanged: { _ in })
      ChatComposer(text: .constant("A draft remains visible."), isEditable: true, send: {})
    }.disabled(true))
  host.sizingOptions = []
  host.view.frame = CGRect(origin: .zero, size: ChatWindowLayout.minimumSize)
  host.view.layoutSubtreeIfNeeded()
  let editor = try #require(navigationView(ChatComposerTextView.self, in: host.view))
  let message = try #require(navigationView(ChatMessageTextView.self, in: host.view))
  #expect(!editor.isEditable)
  #expect(!editor.isHidden)
  #expect(!message.isHidden)
}

@Test @MainActor func chatUtilityPagesKeepOneWindowAndPreserveTheHiddenComposer() async throws {
  let fixture = try await ChatNavigationFixture()
  defer { fixture.close() }
  let controller = ChatSessionWindowController(
    appearance: ThemeEnvironment(), reading: ChatReadingPreferences(defaults: fixture.defaults))
  controller.prepare(
    fixture.session, openSettings: { _ in },
    vault: .init(store: fixture.vault, openRecord: { _ in }))
  defer { controller.close() }
  let window = try #require(controller.window)
  let content = try #require(window.contentView)
  content.layoutSubtreeIfNeeded()
  let editor = try #require(navigationView(ChatComposerTextView.self, in: content))
  let message = try #require(navigationView(ChatMessageTextView.self, in: content))
  let selection = NSRange(location: 3, length: 5)
  editor.setSelectedRange(selection)
  message.setSelectedRange(selection)
  #expect(window.makeFirstResponder(editor))
  for page in [ChatWindowNavigation.Page.memories, .search, .vault] {
    controller.navigation.show(page)
    try await waitForNavigation(content) { editor.isHidden }
    #expect(window.attachedSheet == nil)
    #expect(window.childWindows?.isEmpty != false)
    #expect(controller.window === window)
    #expect(navigationView(ChatComposerTextView.self, in: content) === editor)
    #expect(navigationView(ChatMessageTextView.self, in: content) === message)
    #expect(!editor.isEditable)
    #expect(window.firstResponder !== editor)
    #expect(window.firstResponder !== message)
    #expect(message.isHidden)
    #expect(editor.string == fixture.draft)
    controller.navigation.show(.conversation)
    try await waitForNavigation(content) { !editor.isHidden && editor.isEditable }
    #expect(editor.selectedRange() == selection)
    #expect(message.selectedRange() == selection)
    #expect(!message.isHidden)
    #expect(window.makeFirstResponder(message))
  }
  fixture.session.memoryEditor.begin(.init(role: .user, text: "Remember that I enjoy hiking."))
  try await waitForNavigation(content) { editor.isHidden }
  #expect(window.attachedSheet == nil)
  fixture.session.memoryEditor.close()
  try await waitForNavigation(content) { !editor.isHidden }
  #expect(fixture.session.draft == fixture.draft)
  await fixture.finish()
}

@Test @MainActor func chatUtilityPagesFitTheBubbleInBothThemes() async throws {
  let fixture = try await ChatNavigationFixture()
  defer { fixture.close() }
  let navigation = ChatWindowNavigation()
  for scheme in [ColorScheme.light, .dark] {
    for (page, name) in [
      (ChatWindowNavigation.Page.memories, "memories"), (.search, "search"), (.vault, "vault"),
    ] {
      navigation.show(page)
      try renderSkillInterface(
        ConversationBubbleView(
          presentation: ConversationBubblePresentation(),
          content: ChatSessionView(
            model: fixture.session, openSettings: { _ in }, close: {}, motion: .reduced,
            vault: .init(store: fixture.vault, openRecord: { _ in }), navigation: navigation)
        ).environment(\.colorScheme, scheme),
        size: ChatWindowLayout.minimumSize, name: "sillies-inline-\(name)-\(scheme)")
    }
    fixture.session.memoryEditor.begin(.init(role: .user, text: "Remember that I enjoy hiking."))
    try renderSkillInterface(
      ConversationBubbleView(
        presentation: ConversationBubblePresentation(),
        content: ChatSessionView(
          model: fixture.session, openSettings: { _ in }, close: {}, motion: .reduced,
          navigation: navigation)
      ).environment(\.colorScheme, scheme),
      size: ChatWindowLayout.minimumSize, name: "sillies-inline-memory-editor-\(scheme)")
    fixture.session.memoryEditor.close()
  }
  await fixture.finish()
}

@MainActor private func waitForNavigation(_ view: NSView, until condition: () -> Bool) async throws
{
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while !condition(), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
    view.layoutSubtreeIfNeeded()
  }
  #expect(condition())
}

@MainActor private func navigationView<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
  if let match = view as? View { return match }
  for child in view.subviews {
    if let match = navigationView(type, in: child) { return match }
  }
  return nil
}

@MainActor private final class ChatNavigationFixture {
  let domain = "sillies-chat-navigation-\(UUID())"
  let draft = "Keep my draft and selection while I review memories."
  let defaults: UserDefaults
  let directory: URL
  let session: ChatSession
  let vault: SessionVaultStore

  init() async throws {
    defaults = try #require(UserDefaults(suiteName: domain))
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
    let conversations = ConversationLibrary(directory: directory.appendingPathComponent("Chat"))
    vault = SessionVaultStore(directory: directory.appendingPathComponent("Vault"))
    await vault.waitUntilLoaded()
    session = ChatWindowFixture.makeReadySession(
      conversation: NavigationReply(),
      history: .stored(conversations: conversations, memories: conversations),
      owner: .init(id: "pogo", name: "Pogo"),
      context: .init(materials: vault.library, personalFacts: conversations))
    await session.restoreHistory()
    await session.refreshAvailability()
    session.draft = "Keep me company while I work."
    session.send()
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while session.isWorking, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(session.messages.count == 2)
    session.draft = draft
  }

  func finish() async {
    await withCheckedContinuation { continuation in session.finish { continuation.resume() } }
    await vault.flush()
  }

  func close() {
    defaults.removePersistentDomain(forName: domain)
    removeTestFile(at: directory)
  }
}

private struct NavigationReply: ConversationResponding {
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  { .init(text: "Let's look at your notes.") }
}
