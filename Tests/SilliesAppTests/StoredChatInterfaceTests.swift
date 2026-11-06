import AppKit
import SilliesChat
import SilliesConversationTestSupport
import SilliesCore
import SilliesReasoning
import SilliesVault
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func storedChatPagesSearchesAndKeepsReadingStableDuringANewReply() async throws {
  let supplied = ProcessInfo.processInfo.environment["SILLIES_STORED_HISTORY_DIRECTORY"]
  let directory =
    supplied.map { URL(fileURLWithPath: $0) }
    ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { if supplied == nil { removeTestFile(at: directory) } }
  let fixture = try await Task.detached {
    if supplied != nil { return try StoredConversationFixture.load(at: directory) }
    return try StoredConversationFixture.seed(at: directory, count: 2_000)
  }.value
  let store = ConversationLibrary(directory: directory)
  let reply = HistoryBrowsingReply()
  let session = ChatWindowFixture.makeReadySession(
    conversation: reply, history: .stored(conversations: store, memories: store),
    owner: StoredConversationFixture.owner)
  await session.restoreHistory()
  #expect(session.phase == .ready)
  #expect(session.messages.count <= ConversationPageRequest.defaultLimit)
  #expect(session.hasEarlierMessages)
  let surface = HeadlessStoredChatSurface(session)
  do {
    try await exerciseStoredChat(session, surface: surface, fixture: fixture, reply: reply)
  } catch {
    await finishStoredChat(session, surface: surface)
    throw error
  }
  await finishStoredChat(session, surface: surface)
  #expect(session.history.failure == nil)
  let reopened = try await store.open(StoredConversationFixture.owner)
  #expect(reopened.checkpoint.draft == session.draft)
  #expect(reopened.checkpoint.readingMessageID == session.history.checkpoint.readingMessageID)
  #expect(reopened.page.entries.last?.message.text == HistoryBrowsingReply.answer)
  print(
    "HEADLESS CHAT \(fixture.messageCount): recent/older/search pages, preserved selection during streaming, recent-page return, draft, reading position and saved reply verified without showing a window."
  )
}

@MainActor private func exerciseStoredChat(
  _ session: ChatSession, surface: HeadlessStoredChatSurface,
  fixture: StoredConversationFixture, reply: HistoryBrowsingReply
) async throws {
  let recentIDs = session.messages.map(\.id)
  let initialText = try #require(session.messages.last?.text)
  _ = try await surface.message(containing: initialText)
  let firstRecent = try #require(session.messages.first?.id)
  await session.browser.show(.beforeMessage(firstRecent))
  #expect(session.browser.page?.hasNewer == true)
  #expect(session.messages.map(\.id) == recentIDs)

  let marker = "historyneedle\(fixture.messageCount / 2)"
  await session.browser.search(marker)
  let match = try #require(session.browser.matches.first)
  #expect(match.id == fixture.landmarks[1].id)
  await session.browser.show(.around(match.id))
  let selected = try await surface.message(containing: marker)
  selected.setSelectedRange(NSRange(location: 0, length: 12))
  let selectedRange = selected.selectedRange()
  let oldPage = try #require(session.browser.page?.entries.map(\.id))
  #expect(session.messages.map(\.id) == recentIDs)
  session.browser.rememberPosition(match.id)
  session.draft = "A new thought while I read earlier messages."
  session.send()
  try await waitForChatState { !session.streamedText.isEmpty }
  let clipboard = NSPasteboard.withUniqueName()
  defer { clipboard.releaseGlobally() }
  #expect(selected.writeSelection(to: clipboard, types: selected.writablePasteboardTypes))
  #expect(
    clipboard.string(forType: .string)
      == (selected.string as NSString).substring(with: selectedRange))
  #expect(session.failure == nil && session.isWorking)
  await reply.complete()
  try await waitForChatState { session.phase == .ready }
  #expect(session.browser.page?.entries.map(\.id) == oldPage)
  #expect(selected.selectedRange() == selectedRange)
  #expect(try await surface.message(containing: marker) === selected)
  #expect(session.messages.count <= ConversationPageRequest.maximumLimit)
  #expect(session.messages.last?.text == HistoryBrowsingReply.answer)
  #expect(!surface.window.isVisible)

  session.browser.showLatest()
  #expect(session.history.checkpoint.readingMessageID == nil)
  surface.scrollToBottom()
  #expect(session.browser.page == nil)
  _ = try await surface.message(containing: HistoryBrowsingReply.answer)
  session.draft = "A draft for the next time I return."
  try await session.history.flush()
}

@MainActor private func finishStoredChat(_ session: ChatSession, surface: HeadlessStoredChatSurface)
  async
{
  surface.close()
  await withCheckedContinuation { continuation in
    session.finish { continuation.resume() }
  }
}

@MainActor private final class HeadlessStoredChatSurface {
  let window: NSWindow
  private let host: NSHostingController<ChatSessionView>
  init(_ session: ChatSession) {
    window = NSWindow(
      contentRect: CGRect(origin: .zero, size: ChatWindowLayout.initialSize),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    host = NSHostingController(
      rootView: ChatSessionView(model: session, openSettings: { _ in }, close: {}, motion: .reduced)
    )
    host.sizingOptions = []
    window.contentViewController = host
    host.view.frame = CGRect(origin: .zero, size: ChatWindowLayout.initialSize)
    host.view.layoutSubtreeIfNeeded()
  }
  func close() { window.close() }
  func message(containing value: String) async throws -> NSTextView {
    try await waitForChatState {
      self.host.view.layoutSubtreeIfNeeded()
      return self.textViews(self.host.view).contains { $0.string.contains(value) }
    }
    return try #require(textViews(host.view).first { $0.string.contains(value) })
  }
  func scrollToBottom() {
    host.view.layoutSubtreeIfNeeded()
    guard let scroll = scrollView(host.view), let document = scroll.documentView else { return }
    let y = document.isFlipped ? max(0, document.bounds.height - scroll.contentSize.height) : 0
    scroll.contentView.scroll(to: .init(x: 0, y: y))
    scroll.reflectScrolledClipView(scroll.contentView)
  }
  private func textViews(_ view: NSView) -> [NSTextView] {
    if let text = view as? NSTextView { return [text] }
    return view.subviews.flatMap { textViews($0) }
  }
  private func scrollView(_ view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView { return scroll }
    return view.subviews.lazy.compactMap { self.scrollView($0) }.first
  }
}

@MainActor private func waitForChatState(_ condition: () -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(3))
  while !condition(), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(10))
  }
  try #require(condition(), "The hidden Chat view did not reach the expected state.")
}

private actor HistoryBrowsingReply: ConversationResponding {
  static let answer = "The new reply finished while the earlier conversation remained readable."
  private let release = AsyncStream<Void>.makeStream()
  func complete() {
    release.continuation.yield(())
    release.continuation.finish()
  }
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  {
    try await streamReply(to: context, progress: progress, receive: { _ in })
  }
  func streamReply(
    to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void,
    receive: @escaping ConversationTextSink
  ) async throws -> ChatReply {
    try await receive("The new reply ")
    for await _ in release.stream { break }
    try Task.checkCancellation()
    try await receive("finished while the earlier conversation remained readable.")
    return .init(text: Self.answer)
  }
}
