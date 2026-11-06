import SwiftUI

/// Explain the separate notes capability without implying that speech recognition has failed.
struct AudioReasoningNotice: View {
  let model: AudioSessionPresentation

  var body: some View {
    if let message = model.reasoningAvailability.failureMessage {
      SessionWarningNotice(message: String(localized: "AI notes")) {
        Text(message).textSelection(.enabled)
        Text(
          "Transcription uses \(model.model.name). Summaries and suggestions use a separate text model."
        ).textSelection(.enabled)
        if let openSettings = model.onOpenTextModelSettings {
          Button("Choose a text model…", action: openSettings)
        }
      }
    }
  }
}
