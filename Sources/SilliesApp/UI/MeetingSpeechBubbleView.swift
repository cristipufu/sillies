import SilliesCore
import SwiftUI

struct MeetingSpeechBubbleView: View {
  private static let textInset: CGFloat = 18
  private static let textLineLimit = 6
  private static let rowSpacing: CGFloat = 12
  private static let headerSpacing: CGFloat = 6
  private static let iconSize: CGFloat = 12
  private static let headerSize: CGFloat = 11
  private static let questionSize: CGFloat = 14
  private static let footerSize: CGFloat = 10
  private static let lineSpacing: CGFloat = 3
  let suggestion: MeetingSuggestion

  var body: some View {
    VStack(alignment: .leading, spacing: Self.rowSpacing) {
      HStack(spacing: Self.headerSpacing) {
        Image(systemName: "sparkle").font(.system(size: Self.iconSize, weight: .semibold))
        Text("Maybe ask…").font(.system(size: Self.headerSize, weight: .semibold, design: .rounded))
      }.foregroundStyle(SilliesTheme.accent)
      Text(suggestion.question)
        .font(.system(size: Self.questionSize, weight: .medium, design: .rounded))
        .lineSpacing(Self.lineSpacing).foregroundStyle(SilliesTheme.ink)
        .lineLimit(Self.textLineLimit).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      Spacer(minLength: 0)
      Text("Your meeting companion")
        .font(.system(size: Self.footerSize, weight: .medium)).foregroundStyle(
          SilliesTheme.secondary)
    }
    .padding(Self.textInset)
    .padding(.horizontal, SuggestionBubbleLayout.tailDepth)
    .padding(SuggestionBubbleLayout.shadowInset)
    .frame(width: SuggestionBubbleLayout.size.width, height: SuggestionBubbleLayout.size.height)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Meeting suggestion: \(suggestion.question)")
  }
}

struct SpeechBubbleShape: Shape {
  private static let radius: CGFloat = 18
  private static let tailHalfHeight: CGFloat = 8
  let tail: SuggestionBubbleLayout.Tail
  let tailOffset: CGFloat

  func path(in rect: CGRect) -> Path {
    let depth = SuggestionBubbleLayout.tailDepth
    let left = rect.minX + (tail == .left ? depth : 0)
    let right = rect.maxX - (tail == .right ? depth : 0)
    let radius = Self.radius
    let tip = min(
      max(tailOffset, radius + Self.tailHalfHeight), rect.height - radius - Self.tailHalfHeight)
    var path = Path()
    path.move(to: CGPoint(x: left + radius, y: rect.minY))
    path.addLine(to: CGPoint(x: right - radius, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: right, y: rect.minY + radius), control: CGPoint(x: right, y: rect.minY))
    if tail == .right {
      path.addLine(to: CGPoint(x: right, y: tip - Self.tailHalfHeight))
      path.addLine(to: CGPoint(x: rect.maxX, y: tip))
      path.addLine(to: CGPoint(x: right, y: tip + Self.tailHalfHeight))
    }
    path.addLine(to: CGPoint(x: right, y: rect.maxY - radius))
    path.addQuadCurve(
      to: CGPoint(x: right - radius, y: rect.maxY), control: CGPoint(x: right, y: rect.maxY))
    path.addLine(to: CGPoint(x: left + radius, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: left, y: rect.maxY - radius), control: CGPoint(x: left, y: rect.maxY))
    if tail == .left {
      path.addLine(to: CGPoint(x: left, y: tip + Self.tailHalfHeight))
      path.addLine(to: CGPoint(x: rect.minX, y: tip))
      path.addLine(to: CGPoint(x: left, y: tip - Self.tailHalfHeight))
    }
    path.addLine(to: CGPoint(x: left, y: rect.minY + radius))
    path.addQuadCurve(
      to: CGPoint(x: left + radius, y: rect.minY), control: CGPoint(x: left, y: rect.minY))
    path.closeSubpath()
    return path
  }
}
