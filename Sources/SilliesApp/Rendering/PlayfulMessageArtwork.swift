import AppKit
import QuartzCore
import SilliesCore

/// All playful text shares the same bubble material, sizing, and appearance contract.
@MainActor
final class PlayfulMessageArtwork {
  private enum Design {
    static let maximumTextWidth: CGFloat = 190
    static let padding: CGFloat = 14
    static let bodySize: CGFloat = 13
    static let scoreSize: CGFloat = 24
    static let captionSize: CGFloat = 10
  }
  let layer = CALayer()
  private let bubble = MascotBubbleArtwork()
  private let text = CATextLayer()

  init() {
    layer.addSublayer(bubble.layer)
    layer.addSublayer(text)
    text.isWrapped = true
    text.alignmentMode = .center
    hide()
  }

  func prepare(
    _ prop: PlayfulSceneDefinition.Prop, message: String,
    appearance: NSAppearance, scale: CGFloat
  ) -> CGSize {
    guard [.sign, .letter, .score].contains(prop) else {
      hide()
      return .zero
    }
    let content = attributedMessage(message, prop: prop, appearance: appearance)
    let measured = content.boundingRect(
      with: CGSize(width: Design.maximumTextWidth, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading])
    let inset = SuggestionBubbleLayout.shadowInset
    let depth = SuggestionBubbleLayout.tailDepth
    let size = CGSize(
      width: ceil(measured.width) + (Design.padding + inset) * 2,
      height: ceil(measured.height) + (Design.padding + inset) * 2 + depth)
    let body = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.isHidden = false
    layer.bounds = CGRect(origin: .zero, size: size)
    layer.position = CGPoint(x: size.width / 2, y: size.height / 2)
    bubble.update(
      frame: body,
      path: MascotBubbleContour.path(
        in: CGRect(origin: .zero, size: body.size), tail: .bottom,
        offset: body.width / 2, depth: depth), appearance: appearance)
    text.frame = CGRect(
      x: inset + Design.padding, y: inset + depth + Design.padding,
      width: ceil(measured.width), height: ceil(measured.height))
    text.contentsScale = scale
    text.string = content
    CATransaction.commit()
    return size
  }

  func hide() { layer.isHidden = true }

  private func attributedMessage(
    _ message: String, prop: PlayfulSceneDefinition.Prop, appearance: NSAppearance
  ) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineSpacing = 3
    var ink = NSColor.labelColor
    appearance.performAsCurrentDrawingAppearance {
      ink = NSColor(cgColor: NSColor.labelColor.cgColor) ?? .labelColor
    }
    let content = NSMutableAttributedString(
      string: message,
      attributes: [
        .font: NSFont.roundedFont(ofSize: Design.bodySize, weight: .semibold),
        .foregroundColor: ink, .paragraphStyle: paragraph,
      ])
    if prop == .score, let separator = message.firstIndex(of: "\n") {
      let caption = NSRange(message.startIndex..<separator, in: message)
      let score = NSRange(message.index(after: separator)..<message.endIndex, in: message)
      content.addAttributes(
        [
          .font: NSFont.roundedFont(ofSize: Design.captionSize, weight: .semibold), .kern: 0.6,
        ], range: caption)
      content.addAttribute(
        .font, value: NSFont.roundedFont(ofSize: Design.scoreSize, weight: .bold), range: score)
    }
    return content
  }
}
