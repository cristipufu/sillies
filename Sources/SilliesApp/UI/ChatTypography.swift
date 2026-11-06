import AppKit
import SwiftUI

enum ChatReadingSize: String, CaseIterable {
  case compact, standard, large
  var points: CGFloat {
    switch self {
    case .compact: 12
    case .standard: 14
    case .large: 17
    }
  }
  var title: String {
    switch self {
    case .compact: String(localized: "Small")
    case .standard: String(localized: "Standard")
    case .large: String(localized: "Large")
    }
  }
}

extension EnvironmentValues {
  @Entry var chatReadingSize = ChatReadingSize.standard
}

@MainActor enum ChatTypography {
  static let messageSize: CGFloat = ChatReadingSize.standard.points
  static let minimumLineHeight: CGFloat = 20
  private static let lineSpacing: CGFloat = 2
  private static let paragraphSpacing: CGFloat = 4
  static let messageFont = NSFont.systemFont(ofSize: messageSize)
  static let paragraphStyle: NSParagraphStyle = {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = lineSpacing
    paragraph.paragraphSpacing = paragraphSpacing
    return paragraph
  }()
  static var attributes: [NSAttributedString.Key: Any] {
    [.font: messageFont, .paragraphStyle: paragraphStyle]
  }
  static func attributes(for size: ChatReadingSize) -> [NSAttributedString.Key: Any] {
    [.font: NSFont.systemFont(ofSize: size.points), .paragraphStyle: paragraphStyle]
  }
  static func apply(_ size: ChatReadingSize, to view: NSTextView) {
    guard !view.hasMarkedText(), view.font?.pointSize != size.points else { return }
    let selections = view.selectedRanges
    var typingAttributes = view.typingAttributes
    typingAttributes.merge(attributes(for: size)) { _, updated in updated }
    view.font = NSFont.systemFont(ofSize: size.points)
    view.typingAttributes = typingAttributes
    view.selectedRanges = selections
  }
}
