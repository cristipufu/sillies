import SilliesChat
import SilliesCore
import SwiftUI

/// Chat and the Talk controls expose the same recoveries without owning session work.
struct ChatSessionNotices: View {
  @Environment(\.silliesTheme) private var theme
  let model: ChatSession
  let openSettings: (ChatNotice.SettingsDestination) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if model.export.isExporting {
        HStack {
          ProgressView().controlSize(.small).accessibilityLabel("Exporting conversation")
          Text("Exporting conversation…").font(.caption)
          Text(model.export.exportedMessages, format: .number).font(.caption.monospacedDigit())
            .accessibilityLabel("Exported messages").accessibilityValue(
              Text(model.export.exportedMessages, format: .number))
          Spacer()
          Button("Cancel") { model.export.cancel() }.buttonStyle(SoftButtonStyle())
        }
      } else if let notice = model.export.notice {
        HStack(alignment: .top) {
          Text(notice).font(.caption).textSelection(.enabled)
          Spacer()
          Button("Dismiss") { model.export.dismissNotice() }.buttonStyle(.plain).font(.caption)
        }
      }
      if model.draft.count > ChatContext.maximumMessageCharacters {
        Text(
          "This thought is too long to send. Shorten it to \(ChatContext.maximumMessageCharacters) characters; your words are kept here."
        ).font(.caption)
      }
      if let error = model.history.failure {
        Text(error).font(.caption).textSelection(.enabled)
        Button("Retry saving") { Task { await model.retrySaving() } }.buttonStyle(SoftButtonStyle())
      }
      if let failure = model.failure { SessionFailureNotice(failure: failure) }
      if let notice = model.notice {
        Text(notice.message).font(.caption).foregroundStyle(theme.secondary).textSelection(.enabled)
      }
      if let destination = model.recoverySettingsDestination {
        Button(destination.title) { openSettings(destination) }.buttonStyle(SoftButtonStyle())
      }
      if model.canRetry {
        Button("Try reply again") { model.retry() }.buttonStyle(SoftButtonStyle())
      }
      if model.canContinueSpeaking {
        Button("Continue speaking") { model.continueSpeaking() }.buttonStyle(SoftButtonStyle())
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
