import SilliesCore
import SwiftUI

struct AudioMeetingSuggestionsView: View {
  private static let suggestionRowHeight: CGFloat = 88
  private static let maximumSuggestionsHeight: CGFloat = 152
  let model: AudioSessionPresentation

  var body: some View {
    @Bindable var session = model
    VStack(alignment: .leading, spacing: 12) {
      Toggle(isOn: $session.suggestionsEnabled) {
        Label("Meeting suggestions", systemImage: "pawprint")
          .font(.callout.weight(.semibold))
      }.toggleStyle(.switch).controlSize(.small)
        .disabled(!model.canFinish || model.reasoningNotice != nil)
      if !model.suggestions.isEmpty {
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(model.suggestions.reversed()) { MeetingSuggestionView(suggestion: $0) }
          }
        }.frame(
          height: min(
            CGFloat(model.suggestions.count) * Self.suggestionRowHeight,
            Self.maximumSuggestionsHeight))
      } else {
        Text(
          model.reasoningNotice == nil
            ? "Your companion will quietly flag useful questions as the conversation develops."
            : "Suggestions are unavailable. You can still keep the transcript."
        )
        .font(.caption).foregroundStyle(SilliesTheme.secondary)
      }
    }
    .padding(14).background(
      SilliesTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
  }
}
