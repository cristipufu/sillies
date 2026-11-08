import ApplicationServices
import CoreGraphics
import Foundation

/// A successful AX batch can still contain a stale application element or per-attribute errors.
/// Only a real window with readable geometry can establish a window-role decision.
struct AccessibilityWindowInspection {
  enum Attribute: Int, CaseIterable {
    case role = 0
    case subrole
    case modal
    case minimized
    case closeButton
    case minimizeButton
    case zoomButton
    case fullScreenButton
    case position
    case size

    var key: String {
      switch self {
      case .role: kAXRoleAttribute
      case .subrole: kAXSubroleAttribute
      case .modal: kAXModalAttribute
      case .minimized: kAXMinimizedAttribute
      case .closeButton: kAXCloseButtonAttribute
      case .minimizeButton: kAXMinimizeButtonAttribute
      case .zoomButton: kAXZoomButtonAttribute
      case .fullScreenButton: kAXFullScreenButtonAttribute
      case .position: kAXPositionAttribute
      case .size: kAXSizeAttribute
      }
    }
  }

  static let attributeKeys = Attribute.allCases.map(\.key)

  let frame: CGRect
  let isStandardWindow: Bool

  init?(values: [AnyObject]) {
    guard values.count == Self.attributeKeys.count,
      Self.value(.role, in: values) as? String == kAXWindowRole,
      let frame = Self.frame(in: values)
    else { return nil }

    self.frame = frame
    let subrole = Self.value(.subrole, in: values) as? String
    let isModal = Self.value(.modal, in: values) as? Bool == true
    let isMinimized = Self.value(.minimized, in: values) as? Bool == true
    let hasCloseButton = Self.isElement(.closeButton, in: values)
    let hasWindowControl =
      Self.isElement(.minimizeButton, in: values)
      || Self.isElement(.zoomButton, in: values)
      || Self.isElement(.fullScreenButton, in: values)
    isStandardWindow =
      subrole == kAXStandardWindowSubrole
      && !isModal && !isMinimized && hasCloseButton && hasWindowControl
  }

  private static func value(_ attribute: Attribute, in values: [AnyObject]) -> AnyObject {
    values[attribute.rawValue]
  }

  private static func isElement(_ attribute: Attribute, in values: [AnyObject]) -> Bool {
    CFGetTypeID(value(attribute, in: values)) == AXUIElementGetTypeID()
  }

  private static func frame(in values: [AnyObject]) -> CGRect? {
    let position = value(.position, in: values)
    let dimensions = value(.size, in: values)
    guard CFGetTypeID(position) == AXValueGetTypeID(),
      CFGetTypeID(dimensions) == AXValueGetTypeID()
    else { return nil }
    var origin = CGPoint.zero
    var size = CGSize.zero
    let positionValue = unsafeDowncast(position, to: AXValue.self)
    let sizeValue = unsafeDowncast(dimensions, to: AXValue.self)
    guard AXValueGetValue(positionValue, .cgPoint, &origin),
      AXValueGetValue(sizeValue, .cgSize, &size),
      origin.x.isFinite, origin.y.isFinite,
      size.width.isFinite, size.height.isFinite,
      size.width > 0, size.height > 0
    else { return nil }
    return CGRect(origin: origin, size: size)
  }
}
