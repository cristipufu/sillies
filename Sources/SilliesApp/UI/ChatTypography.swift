import AppKit

@MainActor enum ChatTypography {
  static let messageSize: CGFloat = 16
  static let minimumLineHeight: CGFloat = 22
  private static let lineSpacing: CGFloat = 4
  private static let paragraphSpacing: CGFloat = 6
  static let messageFont: NSFont = {
    let base = NSFont.systemFont(ofSize: messageSize)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: messageSize) ?? base
  }()
  static let paragraphStyle: NSParagraphStyle = {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = lineSpacing
    paragraph.paragraphSpacing = paragraphSpacing
    return paragraph
  }()
  static var attributes: [NSAttributedString.Key: Any] {
    [.font: messageFont, .paragraphStyle: paragraphStyle]
  }
}
