import CoreGraphics
import Foundation

/// Metadata for a candidate window under a dragged companion.
public struct WindowTargetCandidate: Equatable, Sendable {
  public let windowID: UInt32
  public let processID: Int32
  public let appName: String
  public let bundleIdentifier: String?
  public let windowTitle: String?
  public var frame: CGRect
  public var windowLayer: Int
  public var isVisible = true

  public init(
    windowID: UInt32, processID: Int32, appName: String,
    bundleIdentifier: String? = nil, windowTitle: String? = nil, frame: CGRect,
    windowLayer: Int = 0
  ) {
    self.windowID = windowID
    self.processID = processID
    self.appName = appName
    self.bundleIdentifier = bundleIdentifier
    self.windowTitle = windowTitle
    self.frame = frame
    self.windowLayer = windowLayer
  }

  public var displayTitle: String {
    if let windowTitle, !windowTitle.isEmpty, windowTitle != appName {
      return "\(appName) · \(windowTitle)"
    }
    return appName
  }
}
