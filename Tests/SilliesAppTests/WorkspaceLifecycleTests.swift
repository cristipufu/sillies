import AppKit
import Testing

@testable import SilliesApp

@Test @MainActor func workspaceNotificationsDeliverNativeGeometrySynchronouslyAndStopCompletely() {
  let workspace = NotificationCenter()
  let application = NotificationCenter()
  var received: [Notification.Name] = []
  var activations = 0
  let notifications = WorkspaceNotifications(workspace: workspace, application: application) {
    event in
    switch event {
    case .windowChanged(let notification): received.append(notification.name)
    case .activated: activations += 1
    default: break
    }
  }
  for _ in 0..<100 {
    notifications.start()
    notifications.start()
    application.post(name: NSWindow.didMoveNotification, object: nil)
    #expect(received.last == NSWindow.didMoveNotification)
    application.post(name: NSWindow.didResizeNotification, object: nil)
    #expect(received.last == NSWindow.didResizeNotification)
    workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
    notifications.stop()
    let count = received.count
    application.post(name: NSWindow.didMoveNotification, object: nil)
    workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
    #expect(received.count == count)
  }
  #expect(received.count == 200)
  #expect(activations == 100)
}

@Test @MainActor func workspaceFocusSequencesPreserveContinuityAcrossRapidApplicationSwitches() {
  let focus = WorkspaceFocusSession()
  let first = WorkspaceFocusSession.Application(
    processID: 10, name: "Meeting", bundleIdentifier: "test.meeting")
  let second = WorkspaceFocusSession.Application(
    processID: 20, name: "Editor", bundleIdentifier: "test.editor")
  for index in 0..<1_000 {
    let next = index.isMultiple(of: 2) ? first : second
    #expect(focus.needsReplacement(next, for: .applicationChanged))
    focus.follow(next, continuity: .preserveUntilDiscovery)
    #expect(focus.isAwaitingWindow)
    #expect(!focus.needsReplacement(next, for: .applicationChanged))
    #expect(focus.needsReplacement(next, for: .reconcileCurrent))
    focus.resolvedWindow()
    #expect(!focus.isAwaitingWindow)
    #expect(focus.application == next)
  }
  focus.follow(first, continuity: .noPreviousWindow)
  #expect(!focus.isAwaitingWindow)
}
