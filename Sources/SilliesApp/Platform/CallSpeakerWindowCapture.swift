import CoreGraphics
import Foundation
import ScreenCaptureKit

/// One recording owns this cache. Images are transient, tile-cropped, and never encoded or saved.
actor CallSpeakerWindowCapture: CallSpeakerImageCapturing {
  private var window: SCWindow?
  private var isStopped = false

  func capture(_ request: CallSpeakerVisualRequest) async -> CGImage? {
    guard !isStopped, !Task.isCancelled, CGPreflightScreenCaptureAccess() else { return nil }
    do {
      let window = try await resolveWindow(request)
      guard !isStopped, !Task.isCancelled, let window else { return nil }
      let configuration = SCStreamConfiguration()
      configuration.sourceRect = request.layout.crop
      configuration.width = Int(request.layout.crop.width)
      configuration.height = Int(request.layout.crop.height)
      configuration.showsCursor = false
      configuration.ignoreShadowsSingleWindow = true
      configuration.includeChildWindows = false
      configuration.capturesAudio = false
      let image = try await SCScreenshotManager.captureImage(
        contentFilter: SCContentFilter(desktopIndependentWindow: window),
        configuration: configuration)
      guard !isStopped, !Task.isCancelled else { return nil }
      return image
    } catch {
      window = nil
      return nil
    }
  }

  private func resolveWindow(_ request: CallSpeakerVisualRequest) async throws -> SCWindow? {
    if let window, matches(window, request: request) { return window }
    let content = try await SCShareableContent.excludingDesktopWindows(
      true, onScreenWindowsOnly: true)
    guard !isStopped, !Task.isCancelled else { return nil }
    window = content.windows.first { matches($0, request: request) }
    return window
  }

  private func matches(_ window: SCWindow, request: CallSpeakerVisualRequest) -> Bool {
    window.windowID == request.source.windowID
      && window.owningApplication?.processID == request.source.processID
  }

  func stop() {
    isStopped = true
    window = nil
  }
}
