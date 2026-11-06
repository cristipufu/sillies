import SwiftUI

/// Both panes stay mounted so switching does not reset text selection or reading position.
struct AudioMeetingPanes: View {
  @Environment(\.silliesTheme) private var theme
  let model: AudioSessionPresentation

  var body: some View {
    VStack(spacing: 12) {
      Picker(
        "Participate",
        selection: Binding(get: { model.detailPane }, set: { model.selectDetailPane($0) })
      ) {
        Text("Transcript").tag(AudioSessionPresentation.DetailPane.transcript)
        Text("Meeting suggestions").tag(AudioSessionPresentation.DetailPane.suggestions)
      }
      .pickerStyle(.segmented).labelsHidden().controlSize(.large)
      .accessibilityHint(
        model.hasUnreadSuggestion ? String(localized: "A meeting suggestion is ready") : ""
      )
      .overlay(alignment: .topTrailing) {
        if model.hasUnreadSuggestion {
          Circle().fill(theme.accent).frame(width: 7, height: 7)
            .padding(5).allowsHitTesting(false).accessibilityHidden(true)
        }
      }
      ZStack {
        AudioTranscriptView(model: model)
          .opacity(model.detailPane == .transcript ? 1 : 0)
          .allowsHitTesting(model.detailPane == .transcript)
          .disabled(model.detailPane != .transcript)
          .accessibilityHidden(model.detailPane != .transcript)
        AudioMeetingSuggestionsView(model: model)
          .opacity(model.detailPane == .suggestions ? 1 : 0)
          .allowsHitTesting(model.detailPane == .suggestions)
          .disabled(model.detailPane != .suggestions)
          .accessibilityHidden(model.detailPane != .suggestions)
      }
    }
  }
}
