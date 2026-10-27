import AppKit
import CoreGraphics
import ScreenCaptureKit
import SilliesCore

struct WindowSnapshotResult: Sendable {
  let image: CGImage?
  let pngData: Data?
  let extractedText: String
  let summary: String
  let actionItems: [String]
  let errorDescription: String?
}

/// Captures a clean image of a single target window via ScreenCaptureKit and extracts text on-device
/// using the Vision framework.
enum WindowSnapshotService {
  static var hasScreenCapturePermission: Bool {
    CGPreflightScreenCaptureAccess()
  }

  static func openSystemSettings() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    {
      NSWorkspace.shared.open(url)
    }
  }

  /// Clears stale ad-hoc CDHash entries from macOS TCC on a background worker so a freshly built
  /// local app bundle can be cleanly authorized without blocking the UI thread.
  static func resetAndRequestPermission() {
    let bundleID = Bundle.main.bundleIdentifier
    Task.detached(priority: .userInitiated) {
      if let bundleID {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", bundleID]
        do {
          try process.run()
          process.waitUntilExit()
          if process.terminationStatus != 0 {
            fputs(
              "Screen capture permission reset exited with status \(process.terminationStatus)\n",
              stderr)
          }
        } catch {
          fputs("Screen capture permission reset failed: \(error.localizedDescription)\n", stderr)
        }
      }
      _ = CGRequestScreenCaptureAccess()
      await MainActor.run {
        openSystemSettings()
      }
    }
  }

  static func capture(target: WindowTargetCandidate) async -> WindowSnapshotResult {
    let fallback = "Captured window snapshot of \(target.displayTitle)."
    if target.processID == ProcessInfo.processInfo.processIdentifier,
      let localImage = await captureLocalApplicationWindow(windowID: target.windowID)
    {
      return await imageResult(localImage, summary: fallback)
    }

    let hasAccess = await Task.detached(priority: .userInitiated) {
      if CGPreflightScreenCaptureAccess() {
        return true
      }
      _ = CGRequestScreenCaptureAccess()
      return false
    }.value
    guard hasAccess else {
      return WindowSnapshotResult(
        image: nil,
        pngData: nil,
        extractedText: "",
        summary:
          "Screen Recording permission is required to capture \(target.appName). If Sillies is already enabled in System Settings › Privacy & Security › Screen & System Audio Recording, a local rebuild updated the app binary—click “Refresh Permission” below, toggle Sillies back on, and relaunch.",
        actionItems: [],
        errorDescription: "Screen capture permission required")
    }

    let cgImage = await captureWindowImage(target: target)
    guard let cgImage else {
      return WindowSnapshotResult(
        image: nil,
        pngData: nil,
        extractedText: "",
        summary:
          "Could not capture \(target.displayTitle). Make sure the window is visible on screen and not minimized.",
        actionItems: [],
        errorDescription: "Window capture unavailable")
    }
    return await imageResult(cgImage, summary: fallback)
  }

  private static func imageResult(_ image: CGImage, summary: String) async -> WindowSnapshotResult {
    let pngData = await Task.detached(priority: .utility) {
      SessionVaultStore.encodePNGData(from: image)
    }.value
    return WindowSnapshotResult(
      image: image, pngData: pngData, extractedText: "",
      summary: summary, actionItems: [],
      errorDescription: pngData == nil ? "Could not encode the snapshot image." : nil)
  }

  private static func captureWindowImage(target: WindowTargetCandidate) async -> CGImage? {
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: false)
      guard let scWindow = content.windows.first(where: { $0.windowID == target.windowID }) else {
        return nil
      }
      let filter = SCContentFilter(desktopIndependentWindow: scWindow)
      let config = SCStreamConfiguration()
      let scale = max(Int(filter.pointPixelScale.rounded()), 2)
      config.width = max(Int(scWindow.frame.width) * scale, 1)
      config.height = max(Int(scWindow.frame.height) * scale, 1)
      config.showsCursor = false
      config.ignoreShadowsSingleWindow = true
      return try await SCScreenshotManager.captureImage(
        contentFilter: filter, configuration: config)
    } catch {
      fputs("Window capture failed: \(error.localizedDescription)\n", stderr)
      return nil
    }
  }

  @MainActor
  private static func captureLocalApplicationWindow(windowID: CGWindowID) -> CGImage? {
    guard let window = NSApp.window(withWindowNumber: Int(windowID)),
      let view = window.contentView,
      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
    else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep.cgImage
  }

}
