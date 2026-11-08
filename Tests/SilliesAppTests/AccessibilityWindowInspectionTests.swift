import ApplicationServices
import Foundation
import Testing

@testable import SilliesApp

@Test func accessibilityApplicationElementsCannotVerifyAnEmptyWindowList() throws {
  var error = AXError.attributeUnsupported
  let unsupported = try #require(AXValueCreate(.axError, &error))
  var values = [AnyObject](
    repeating: unsupported, count: AccessibilityWindowInspection.attributeKeys.count)
  values[AccessibilityWindowInspection.Attribute.role.rawValue] = kAXApplicationRole as NSString
  #expect(AccessibilityWindowInspection(values: values) == nil)

  // Reproduces startup's safe WindowServer fallback when every AX element is unreadable.
  let visibleWindow = WindowServerSource.Candidate(
    id: 42, layer: 0, frame: CGRect(x: 180, y: 140, width: 1_200, height: 720))
  #expect(
    WindowServerSource.chooseCandidate(
      from: [visibleWindow], preferredFrame: nil, preferredPoint: nil,
      currentWindowID: nil, roleSnapshot: AccessibilityWindowRoleSnapshot(),
      requiresVerifiedFloatingRole: true)?.id == visibleWindow.id)
  #expect(
    WindowServerSource.chooseCandidate(
      from: [visibleWindow], preferredFrame: nil, preferredPoint: nil,
      currentWindowID: nil,
      roleSnapshot: AccessibilityWindowRoleSnapshot(hasVerifiedWindowList: true),
      requiresVerifiedFloatingRole: true) == nil)
}

@Test func accessibilityWindowInspectionPreservesVerifiedMinimizedAndModalWindows() throws {
  let values = try standardWindowAttributes()
  let standard = try #require(AccessibilityWindowInspection(values: values))
  #expect(standard.isStandardWindow)
  #expect(standard.frame == CGRect(x: 180, y: 140, width: 1_200, height: 720))

  for attribute in [AccessibilityWindowInspection.Attribute.minimized, .modal] {
    var unavailable = values
    unavailable[attribute.rawValue] = NSNumber(value: true)
    let inspection = try #require(AccessibilityWindowInspection(values: unavailable))
    #expect(!inspection.isStandardWindow)
    #expect(inspection.frame == standard.frame)
  }
}

@Test func accessibilityWindowInspectionRejectsUnreadableAndInvalidGeometry() throws {
  let values = try standardWindowAttributes()
  #expect(AccessibilityWindowInspection(values: Array(values.dropLast())) == nil)
  for attribute in [AccessibilityWindowInspection.Attribute.position, .size] {
    var unreadable = values
    var error = AXError.cannotComplete
    unreadable[attribute.rawValue] = try #require(AXValueCreate(.axError, &error))
    #expect(AccessibilityWindowInspection(values: unreadable) == nil)
  }
  for width in [CGFloat.zero, -1, .nan, .infinity] {
    var invalid = values
    var size = CGSize(width: width, height: 720)
    invalid[AccessibilityWindowInspection.Attribute.size.rawValue] = try #require(
      AXValueCreate(.cgSize, &size))
    #expect(AccessibilityWindowInspection(values: invalid) == nil)
  }
}

private func standardWindowAttributes() throws -> [AnyObject] {
  let element = AXUIElementCreateApplication(getpid())
  var position = CGPoint(x: 180, y: 140)
  var size = CGSize(width: 1_200, height: 720)
  let positionValue = try #require(AXValueCreate(.cgPoint, &position))
  let sizeValue = try #require(AXValueCreate(.cgSize, &size))
  return AccessibilityWindowInspection.Attribute.allCases.map { attribute in
    switch attribute {
    case .role: kAXWindowRole as NSString
    case .subrole: kAXStandardWindowSubrole as NSString
    case .modal, .minimized: NSNumber(value: false)
    case .closeButton, .minimizeButton, .zoomButton, .fullScreenButton: element
    case .position: positionValue
    case .size: sizeValue
    }
  }
}
