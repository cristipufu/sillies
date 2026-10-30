import AppKit
import Observation

/// Owns application identity and continuity while asynchronous window discovery is in flight.
@MainActor @Observable
final class WorkspaceFocusSession {
  enum Refresh { case applicationChanged, reconcileCurrent }
  enum Continuity { case noPreviousWindow, preserveUntilDiscovery }
  struct Application: Equatable {
    let processID: pid_t
    let name: String
    let bundleIdentifier: String?
  }
  private(set) var application = Application(
    processID: 0, name: "Your desktop", bundleIdentifier: nil)
  private(set) var isAwaitingWindow = false

  func frontmostReplacement(for refresh: Refresh) -> Application? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let candidate = Application(
      processID: app.processIdentifier, name: app.localizedName ?? "Your app",
      bundleIdentifier: app.bundleIdentifier)
    guard needsReplacement(candidate, for: refresh), isTrackable(app) else { return nil }
    return candidate
  }

  func needsReplacement(_ candidate: Application, for refresh: Refresh) -> Bool {
    refresh == .reconcileCurrent || application.processID != candidate.processID
  }

  func follow(_ application: Application, continuity: Continuity) {
    self.application = application
    isAwaitingWindow = continuity == .preserveUntilDiscovery
  }

  func resolvedWindow() { isAwaitingWindow = false }

  private func isTrackable(_ app: NSRunningApplication) -> Bool {
    guard app.processIdentifier == ProcessInfo.processInfo.processIdentifier else {
      return TrackableApplicationPolicy.isTrackable(app)
    }
    if NSApp.keyWindow is CompanionUtilityWindow { return false }
    return NSApp.windows.contains {
      $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain && $0.styleMask.contains(.titled)
    }
  }
}
