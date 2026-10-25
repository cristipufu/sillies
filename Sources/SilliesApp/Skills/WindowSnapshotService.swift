import AppKit
import CoreGraphics
import ScreenCaptureKit
import SilliesCore
import Vision

struct WindowSnapshotResult: Sendable {
  let image: CGImage?
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

  /// Clears stale ad-hoc CDHash entries from macOS TCC so a freshly built local app bundle
  /// can be cleanly authorized in System Settings › Privacy & Security › Screen & System Audio Recording.
  static func resetAndRequestPermission() {
    if let bundleID = Bundle.main.bundleIdentifier {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
      process.arguments = ["reset", "ScreenCapture", bundleID]
      try? process.run()
      process.waitUntilExit()
    }
    _ = CGRequestScreenCaptureAccess()
    openSystemSettings()
  }

  static func capture(target: WindowTargetCandidate) async -> WindowSnapshotResult {
    if target.processID == ProcessInfo.processInfo.processIdentifier,
      let localImage = await captureLocalApplicationWindow(windowID: target.windowID)
    {
      let recognizedText = await recognizeText(in: localImage)
      let fallback = "Captured window snapshot of \(target.displayTitle)."
      let (summary, actions) = SessionSummarizer.summarize(
        text: recognizedText, fallbackContext: fallback)
      return WindowSnapshotResult(
        image: localImage,
        extractedText: recognizedText,
        summary: summary,
        actionItems: actions,
        errorDescription: nil)
    }

    guard CGPreflightScreenCaptureAccess() else {
      _ = CGRequestScreenCaptureAccess()
      return WindowSnapshotResult(
        image: nil,
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
        extractedText: "",
        summary:
          "Could not capture \(target.displayTitle). Make sure the window is visible on screen and not minimized.",
        actionItems: [],
        errorDescription: "Window capture unavailable")
    }
    let recognizedText = await recognizeText(in: cgImage)
    let fallback = "Captured window snapshot of \(target.displayTitle)."
    let (summary, actions) = SessionSummarizer.summarize(
      text: recognizedText, fallbackContext: fallback)
    return WindowSnapshotResult(
      image: cgImage,
      extractedText: recognizedText,
      summary: summary,
      actionItems: actions,
      errorDescription: nil)
  }

  private static func captureWindowImage(target: WindowTargetCandidate) async -> CGImage? {
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: false)
      let matchedWindow =
        content.windows.first { $0.windowID == target.windowID }
        ?? content.windows.first {
          $0.owningApplication?.processID == target.processID && $0.frame.width >= 120
            && $0.isOnScreen
        }
        ?? content.windows.first {
          $0.owningApplication?.processID == target.processID && $0.frame.width >= 120
        }
      guard let scWindow = matchedWindow else { return nil }
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

  private static func recognizeText(in image: CGImage) async -> String {
    await Task.detached(priority: .userInitiated) {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      let handler = VNImageRequestHandler(cgImage: image, options: [:])
      do {
        try handler.perform([request])
        let observations = request.results ?? []
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
      } catch {
        return ""
      }
    }.value
  }
}
