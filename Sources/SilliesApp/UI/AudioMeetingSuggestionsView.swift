import SilliesCore
import SwiftUI

struct AudioMeetingSuggestionsView: View {
  @Environment(\.silliesTheme) private var theme
  let model: AudioSessionPresentation

  var body: some View {
    @Bindable var session = model
    VStack(alignment: .leading, spacing: 12) {
      Toggle(isOn: $session.suggestionsEnabled) {
        Label("Meeting suggestions", systemImage: "pawprint")
          .font(.callout.weight(.semibold))
      }.toggleStyle(.switch).controlSize(.small)
        .disabled(!model.canFinish || model.reasoningNotice != nil)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if let notice = model.reasoningNotice {
            SessionWarningNotice(message: notice) { EmptyView() }
          }
          if model.suggestions.isEmpty {
            emptyState
          } else {
            ForEach(model.suggestions.reversed()) { MeetingSuggestionView(suggestion: $0) }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollBounceBehavior(.basedOnSize)
      .defaultScrollAnchor(.top)
    }
    .padding(16).background(theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.border, lineWidth: 1))
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "pawprint").font(.title).foregroundStyle(theme.accent)
      Text(
        model.reasoningNotice == nil
          ? String(
            localized:
              "Your companion will quietly flag useful questions as the conversation develops.")
          : String(localized: "Suggestions are unavailable. You can still keep the transcript.")
      )
      .font(.callout).foregroundStyle(theme.secondary)
      .multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity).padding(.vertical, 32).padding(.horizontal, 16)
  }
}
