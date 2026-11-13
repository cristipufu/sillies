import ApplicationServices
import CoreGraphics
import Foundation
import SilliesCore

/// All callers are confined to CallWindowSpeakerReader's actor. No AX handles leave it.
enum CallSpeakerAX {
  static let timeout: Float = 0.015
  static let maximumWindows = 64
  static let maximumChildren = 256
  enum Attribute: String {
    case role = "AXRole"
    case title = "AXTitle"
    case description = "AXDescription"
    case identifier = "AXIdentifier"
    case position = "AXPosition"
    case size = "AXSize"
    case number = "AXWindowNumber"
    case minimized = "AXMinimized"
    case classes = "AXDOMClassList"
    case url = "AXURL"
    case value = "AXValue"
    case rowCount = "AXRowCount"
  }
  static func values(_ attributes: [Attribute], of element: AXUIElement) -> [Attribute: AnyObject] {
    guard
      let values = AccessibilityWindowSource.CallMetadata.values(
        attributes.map(\.rawValue), of: element)
    else { return [:] }
    return Dictionary(zip(attributes, values), uniquingKeysWith: { _, latest in latest })
  }
  static func string(_ attribute: Attribute, of element: AXUIElement) -> String? {
    values([attribute], of: element)[attribute] as? String
  }
  static func elements(_ attribute: String, of element: AXUIElement, limit: Int) -> [AXUIElement]? {
    AccessibilityWindowSource.CallMetadata.elements(attribute, of: element, limit: limit)
  }

  static func frame(_ values: [Attribute: AnyObject]) -> CGRect? {
    guard let position = values[.position], let size = values[.size],
      CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
    else { return nil }
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point),
      AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions),
      point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
      dimensions.width > 0, dimensions.height > 0
    else { return nil }
    return CGRect(origin: point, size: dimensions)
  }
  static func matches(_ element: AXUIElement, request: CallSpeakerReadRequest) -> Bool {
    let values = values([.role, .number, .position, .size, .title, .minimized], of: element)
    return matches(values: values, request: request)
  }
  static func matches(values: [Attribute: AnyObject], request: CallSpeakerReadRequest) -> Bool {
    guard values[.role] as? String == kAXWindowRole, values[.minimized] as? Bool != true,
      let frame = frame(values)
    else { return false }
    if let number = values[.number] as? NSNumber {
      guard number.doubleValue.isFinite, let identifier = UInt32(exactly: number) else {
        return false
      }
      return identifier == request.target.windowID
    }
    let converted = ScreenCoordinates.appKitRect(
      fromAccessibility: frame, primaryScreenTop: request.primaryScreenTop)
    guard WindowFrameComparison.matches(converted, request.target.frame),
      let expected = request.verifiedTitle ?? request.target.windowTitle, !expected.isEmpty,
      values[.title] as? String == expected
    else { return false }
    return true
  }
}
