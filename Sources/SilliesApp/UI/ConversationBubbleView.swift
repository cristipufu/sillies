import SilliesCore
import SwiftUI

@MainActor @Observable
final class ConversationBubblePresentation {
  var tail = ConversationBubbleLayout.Tail.top
  var tailOffset: CGFloat = 200
}

private enum ConversationBubbleMetrics { static let cornerRadius: CGFloat = 24 }

struct ConversationBubbleView<Content: View>: View {
  @Environment(\.silliesTheme) private var theme
  let presentation: ConversationBubblePresentation
  let content: Content
  var body: some View {
    let tail = ConversationBubbleLayout.tailHeight
    VStack(spacing: 0) {
      if presentation.tail == .top { Color.clear.frame(height: tail) }
      content.clipShape(RoundedRectangle(cornerRadius: ConversationBubbleMetrics.cornerRadius))
      if presentation.tail == .bottom { Color.clear.frame(height: tail) }
    }
    .background(shape.fill(theme.paper))
    .overlay(shape.strokeBorder(theme.border, lineWidth: 1))
  }
  private var shape: ConversationBubbleShape {
    .init(tail: presentation.tail, offset: presentation.tailOffset)
  }
}

private struct ConversationBubbleShape: InsettableShape {
  let tail: ConversationBubbleLayout.Tail
  let offset: CGFloat
  var inset: CGFloat = 0
  func inset(by amount: CGFloat) -> Self {
    var copy = self
    copy.inset += amount
    return copy
  }
  func path(in rect: CGRect) -> Path {
    let rect = rect.insetBy(dx: inset, dy: inset)
    let height = ConversationBubbleLayout.tailHeight
    let body = CGRect(
      x: rect.minX, y: rect.minY + (tail == .top ? height : 0),
      width: rect.width, height: max(0, rect.height - height))
    let radius = min(ConversationBubbleMetrics.cornerRadius, min(body.width, body.height) / 2)
    var path = Path()
    path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
    if tail == .top {
      path.addLine(to: CGPoint(x: offset - height, y: body.minY))
      path.addLine(to: CGPoint(x: offset, y: rect.minY))
      path.addLine(to: CGPoint(x: offset + height, y: body.minY))
    }
    path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
    path.addQuadCurve(
      to: CGPoint(x: body.maxX, y: body.minY + radius), control: CGPoint(x: body.maxX, y: body.minY)
    )
    path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
    path.addQuadCurve(
      to: CGPoint(x: body.maxX - radius, y: body.maxY), control: CGPoint(x: body.maxX, y: body.maxY)
    )
    if tail == .bottom {
      path.addLine(to: CGPoint(x: offset + height, y: body.maxY))
      path.addLine(to: CGPoint(x: offset, y: rect.maxY))
      path.addLine(to: CGPoint(x: offset - height, y: body.maxY))
    }
    path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
    path.addQuadCurve(
      to: CGPoint(x: body.minX, y: body.maxY - radius), control: CGPoint(x: body.minX, y: body.maxY)
    )
    path.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
    path.addQuadCurve(
      to: CGPoint(x: body.minX + radius, y: body.minY), control: CGPoint(x: body.minX, y: body.minY)
    )
    path.closeSubpath()
    return path
  }
}
