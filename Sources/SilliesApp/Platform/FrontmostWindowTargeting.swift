import AppKit
import SilliesCore

/// An explicit command takes one fresh metadata snapshot, independently of mascot tracking.
struct FrontmostApplication: Sendable, Equatable {
  let processID: Int32
  let name: String
  let bundleIdentifier: String?

  @MainActor static var current: Self? {
    guard let app = NSWorkspace.shared.frontmostApplication,
      app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
      TrackableApplicationPolicy.isTrackable(app)
    else { return nil }
    return Self(
      processID: app.processIdentifier, name: app.localizedName ?? "App",
      bundleIdentifier: app.bundleIdentifier)
  }
}

struct FrontmostWindowTargeting: Sendable {
  private let queue = DispatchQueue(label: "app.sillies.command-target", qos: .userInitiated)

  func resolve(_ app: FrontmostApplication, primaryScreenTop: Double) async
    -> WindowTargetCandidate?
  {
    await withCheckedContinuation { continuation in
      queue.async {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let snapshot = WindowMetadataReader.snapshot([.optionOnScreenOnly], kCGNullWindowID)
        else {
          continuation.resume(returning: nil)
          return
        }
        let roles = AccessibilityWindowSource.roleSnapshot(for: app.processID)
        let candidates = WindowServerSource.extractCandidates(
          from: snapshot.entries, for: app.processID, currentWindowID: nil)
        let chosen = WindowServerSource.chooseCandidate(
          from: candidates, preferredFrame: roles?.focusedStandardWindowFrame,
          preferredPoint: nil, currentWindowID: nil, roleSnapshot: roles,
          requiresVerifiedFloatingRole: true)
        continuation.resume(
          returning: chosen.map {
            WindowTargetCandidate(
              windowID: $0.id, processID: app.processID, appName: app.name,
              bundleIdentifier: app.bundleIdentifier,
              frame: ScreenCoordinates.appKitRect(
                fromAccessibility: $0.frame, primaryScreenTop: primaryScreenTop),
              windowLayer: $0.layer)
          })
      }
    }
  }
}
