import AppKit

/// Owns subscription lifetime. Native window notifications are forwarded synchronously.
@MainActor
final class WorkspaceNotifications: NSObject {
  enum Event {
    case activated, visibilityChanged, spaceChanged, suspended, resumed, environmentChanged,
      displaysChanged
    case windowChanged(Notification)
  }
  private let workspace: NotificationCenter
  private let application: NotificationCenter
  private let receive: (Event) -> Void
  private var observing = false

  init(
    workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
    application: NotificationCenter = .default, receive: @escaping (Event) -> Void
  ) {
    self.workspace = workspace
    self.application = application
    self.receive = receive
  }

  func start() {
    guard !observing else { return }
    observing = true
    for name in Self.workspaceEvents.keys {
      workspace.addObserver(self, selector: #selector(workspaceChanged), name: name, object: nil)
    }
    for name in Self.applicationEvents.keys {
      application.addObserver(
        self, selector: #selector(applicationChanged), name: name, object: nil)
    }
    for name in Self.windowEvents {
      application.addObserver(self, selector: #selector(windowChanged), name: name, object: nil)
    }
  }

  func stop() {
    observing = false
    workspace.removeObserver(self)
    application.removeObserver(self)
  }

  @objc private func workspaceChanged(_ notification: Notification) {
    guard observing, let event = Self.workspaceEvents[notification.name] else { return }
    receive(event)
  }
  @objc private func applicationChanged(_ notification: Notification) {
    guard observing, let event = Self.applicationEvents[notification.name] else { return }
    receive(event)
  }
  @objc private func windowChanged(_ notification: Notification) {
    guard observing else { return }
    receive(.windowChanged(notification))
  }

  private static let workspaceEvents: [Notification.Name: Event] = [
    NSWorkspace.didActivateApplicationNotification: .activated,
    NSWorkspace.didHideApplicationNotification: .visibilityChanged,
    NSWorkspace.didUnhideApplicationNotification: .visibilityChanged,
    NSWorkspace.didTerminateApplicationNotification: .visibilityChanged,
    NSWorkspace.activeSpaceDidChangeNotification: .spaceChanged,
    NSWorkspace.willSleepNotification: .suspended,
    NSWorkspace.screensDidSleepNotification: .suspended,
    NSWorkspace.sessionDidResignActiveNotification: .suspended,
    NSWorkspace.didWakeNotification: .resumed,
    NSWorkspace.screensDidWakeNotification: .resumed,
    NSWorkspace.sessionDidBecomeActiveNotification: .resumed,
    NSWorkspace.accessibilityDisplayOptionsDidChangeNotification: .environmentChanged,
  ]
  private static let applicationEvents: [Notification.Name: Event] = [
    NSApplication.didChangeScreenParametersNotification: .displaysChanged,
    .NSProcessInfoPowerStateDidChange: .environmentChanged,
  ]
  private static let windowEvents: [Notification.Name] = [
    NSWindow.didMoveNotification, NSWindow.didResizeNotification,
    NSWindow.didBecomeMainNotification, NSWindow.didBecomeKeyNotification,
    NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification,
    NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
  ]
}
