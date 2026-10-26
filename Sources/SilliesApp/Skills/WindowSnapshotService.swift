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

  /// Clears stale ad-hoc CDHash entries from macOS TCC on a background worker so a freshly built
  /// local app bundle can be cleanly authorized without blocking the UI thread.
  static func resetAndRequestPermission() {
    let bundleID = Bundle.main.bundleIdentifier
    Task.detached(priority: .userInitiated) {
      if let bundleID {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", bundleID]
        try? process.run()
        process.waitUntilExit()
      }
      await MainActor.run {
        _ = CGRequestScreenCaptureAccess()
        openSystemSettings()
      }
    }
  }

  static func capture(target: WindowTargetCandidate) async -> WindowSnapshotResult {
    let fallback = "Captured window snapshot of \(target.displayTitle)."
    if target.processID == ProcessInfo.processInfo.processIdentifier,
      let localImage = await captureLocalApplicationWindow(windowID: target.windowID)
    {
      let (recognizedText, summary, actions) = await recognizeAndSummarize(
        in: localImage, fallbackContext: fallback)
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
    let (recognizedText, summary, actions) = await recognizeAndSummarize(
      in: cgImage, fallbackContext: fallback)
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

  private static func recognizeAndSummarize(
    in image: CGImage, fallbackContext: String
  ) async -> (String, String, [String]) {
    await Task.detached(priority: .userInitiated) {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      let handler = VNImageRequestHandler(cgImage: image, options: [:])
      let recognizedText: String
      do {
        try handler.perform([request])
        let observations = request.results ?? []
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        recognizedText = lines.joined(separator: "\n")
      } catch {
        recognizedText = ""
      }
      let (summary, actions) = SessionSummarizer.summarize(
        text: recognizedText, fallbackContext: fallbackContext)
      return (recognizedText, summary, actions)
    }.value
  }
}
