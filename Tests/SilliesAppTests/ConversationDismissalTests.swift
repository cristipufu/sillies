import AppKit
import SilliesCore
import SilliesReasoning
import Testing

@testable import SilliesApp

private struct DismissalReply: ConversationResponding {
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  {
    .init(text: "Hello.")
  }
}

@Test @MainActor func chatOutsideClicksWaitForReleaseAndKeepHostDragsOpen() throws {
  let chat = dismissalWindow()
  let host = dismissalWindow()
  defer {
    chat.close()
    host.close()
  }
  let monitor = ConversationWindowDismissal()
  defer { monitor.stop() }
  var closed = 0
  monitor.start(window: chat) { closed += 1 }
  monitor.handleLocalEvent(try mouse(.leftMouseDown, in: host))
  #expect(closed == 0 && monitor.isMonitoring)
  monitor.handleLocalEvent(try mouse(.leftMouseDragged, in: host))
  monitor.handleLocalEvent(try mouse(.leftMouseUp, in: host))
  #expect(closed == 0 && monitor.isMonitoring)
  monitor.handleLocalEvent(try mouse(.leftMouseDown, in: host))
  monitor.handleLocalEvent(try mouse(.leftMouseUp, in: host))
  #expect(closed == 1 && !monitor.isMonitoring)
  monitor.handleLocalEvent(try mouse(.leftMouseUp, in: host))
  #expect(closed == 1)
}

@Test @MainActor func chatOwnControlsAndMenusDoNotDismissIt() throws {
  let chat = dismissalWindow()
  let menu = dismissalWindow()
  menu.level = .popUpMenu
  defer {
    chat.close()
    menu.close()
  }
  let monitor = ConversationWindowDismissal()
  defer { monitor.stop() }
  var closed = 0
  monitor.start(window: chat) { closed += 1 }
  for window in [chat, menu] {
    monitor.handleLocalEvent(try mouse(.leftMouseDown, in: window))
    monitor.handleLocalEvent(try mouse(.leftMouseUp, in: window))
  }
  #expect(closed == 0 && monitor.isMonitoring)
  monitor.stop()
  #expect(!monitor.isMonitoring)
}

@Test @MainActor func outsideChatDismissalUsesTheSessionClosePathAndKeepsDraft() throws {
  let session = ChatWindowFixture.makeReadySession(conversation: DismissalReply())
  session.draft = "Keep my unfinished thought."
  let controller = ChatSessionWindowController(
    appearance: ThemeEnvironment(), reading: .init(size: .standard))
  controller.prefersReducedMotion = { true }
  defer {
    controller.close()
    session.finish {}
  }
  controller.prepare(session, openSettings: { _ in })
  let window = try #require(controller.window)
  #expect(!controller.dismissal.isMonitoring)
  var finished = 0
  session.onFinish = {
    finished += 1
    session.finish {}
  }
  controller.dismissal.start(window: window) { controller.dismissConversation() }
  let host = dismissalWindow()
  defer { host.close() }
  controller.dismissal.handleLocalEvent(try mouse(.leftMouseDown, in: host))
  controller.dismissal.handleLocalEvent(try mouse(.leftMouseUp, in: host))
  #expect(finished == 1)
  #expect(controller.window == nil && !controller.dismissal.isMonitoring)
  #expect(session.draft == "Keep my unfinished thought.")
}

@Test @MainActor func chatNativeDismissalStopsMonitoringInTalkAndRestartsForChat() async throws {
  let session = ChatWindowFixture.makeReadySession(conversation: DismissalReply())
  let controller = ChatSessionWindowController(
    appearance: ThemeEnvironment(), reading: .init(size: .standard))
  controller.prefersReducedMotion = { true }
  defer {
    controller.close()
    session.finish {}
  }
  controller.show(session, openSettings: { _ in })
  #expect(controller.dismissal.isMonitoring)
  await session.startTalk()
  for _ in 0..<100 {
    if !controller.dismissal.isMonitoring { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(!controller.dismissal.isMonitoring)
  session.showChat()
  for _ in 0..<100 {
    if controller.dismissal.isMonitoring { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(controller.dismissal.isMonitoring)
  controller.close()
  #expect(!controller.dismissal.isMonitoring)
}

@MainActor private func dismissalWindow() -> NSWindow {
  _ = NSApplication.shared
  let window = NSWindow(
    contentRect: .init(x: 100, y: 100, width: 400, height: 300),
    styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  return window
}

@MainActor private func mouse(_ type: NSEvent.EventType, in window: NSWindow) throws -> NSEvent {
  try #require(
    NSEvent.mouseEvent(
      with: type, location: .init(x: 20, y: 20), modifierFlags: [], timestamp: 1,
      windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
}
