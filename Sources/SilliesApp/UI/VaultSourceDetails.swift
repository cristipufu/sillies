import SilliesCore
import SwiftUI

struct VaultSourceDetails: View {
  @Environment(\.silliesTheme) private var theme
  let source: SessionRecordHeader
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Source & processing").font(.headline)
      detail(String(localized: "App"), source.appName)
      detail(String(localized: "Companion"), source.characterName)
      if let language = source.languageIdentifier {
        detail(
          String(localized: "Language"),
          Locale.current.localizedString(forIdentifier: language) ?? language)
      }
      if let speech = source.speechProvenance {
        model(speech, title: String(localized: "Transcription"))
      }
      if let speakers = source.diarizationProvenance {
        model(speakers, title: String(localized: "Speaker detection"))
      }
      if let note = source.processingNote {
        Text(note).font(.caption).foregroundStyle(theme.secondary)
      }
    }.textSelection(.enabled).padding(18).frame(width: 300, alignment: .leading)
      .foregroundStyle(theme.ink).background(theme.paper)
  }
  private func detail(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label).font(.caption).foregroundStyle(theme.secondary)
      Text(value).font(.callout)
    }
  }
  private func model(_ model: SpeechProvenance, title: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      detail(title, model.modelName)
      Text(model.revision).font(.caption2.monospaced()).foregroundStyle(theme.secondary).lineLimit(
        2)
    }
  }
}
