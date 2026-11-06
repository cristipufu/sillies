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
        .disabled(!model.canFinish || !model.reasoningAvailability.isAvailable)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          AudioReasoningNotice(model: model)
          if model.reasoningAvailability == .checking {
            ProgressView("Checking local notes availability…").controlSize(.small)
          }
          if model.suggestions.isEmpty, model.reasoningAvailability.isAvailable {
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
      Text("Your companion will quietly flag useful questions as the conversation develops.")
        .font(.callout).foregroundStyle(theme.secondary)
        .multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity).padding(.vertical, 32).padding(.horizontal, 16)
  }
}
