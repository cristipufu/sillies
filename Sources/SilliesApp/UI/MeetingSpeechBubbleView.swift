import SilliesCore
import SwiftUI

struct MeetingSpeechBubbleView: View {
  @Environment(\.colorScheme) private var colorScheme
  private static let textInset: CGFloat = 12
  private static let rowSpacing: CGFloat = 8
  private static let headerSpacing: CGFloat = 6
  private static let iconSize: CGFloat = 10
  private static let headerSize: CGFloat = 10
  private static let questionSize: CGFloat = 14
  private static let lineSpacing: CGFloat = 3
  let suggestion: MeetingSuggestion
  private var accent: Color {
    colorScheme == .dark ? Color(red: 0.78, green: 0.72, blue: 0.94) : SilliesTheme.accent
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Self.rowSpacing) {
      HStack(spacing: Self.headerSpacing) {
        Image(systemName: "sparkle").font(.system(size: Self.iconSize, weight: .semibold))
          .frame(width: 20, height: 20)
          .background(accent.opacity(0.09), in: Circle())
        Text("A THOUGHT").font(.system(size: Self.headerSize, weight: .semibold, design: .rounded))
          .tracking(0.9)
      }.foregroundStyle(accent)
      Text(suggestion.question)
        .font(.system(size: Self.questionSize, weight: .medium, design: .rounded))
        .lineSpacing(Self.lineSpacing).foregroundStyle(SilliesTheme.ink)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(Self.textInset)
    .padding(.horizontal, SuggestionBubbleLayout.tailDepth)
    .padding(SuggestionBubbleLayout.shadowInset)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Meeting suggestion: \(suggestion.question)")
  }
}

struct SpeechBubbleShape: Shape {
  let tail: SuggestionBubbleLayout.Tail
  let tailOffset: CGFloat

  func path(in rect: CGRect) -> Path {
    Path(
      MascotBubbleContour.path(
        in: rect, tail: tail == .left ? .left : .right,
        offset: tailOffset, depth: SuggestionBubbleLayout.tailDepth))
  }
}
