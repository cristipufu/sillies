import SilliesCore
import SwiftUI

struct MeetingSuggestionView: View {
  @Environment(\.silliesTheme) private var theme
  let suggestion: MeetingSuggestion
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Label(suggestion.question, systemImage: "pawprint.fill").font(.callout.weight(.semibold))
      Text("\(SessionRecord.formatDuration(suggestion.elapsed)) · “\(suggestion.evidence)”")
        .font(.caption).foregroundStyle(theme.secondary)
    }
    .textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.card, in: RoundedRectangle(cornerRadius: 10))
  }
}
