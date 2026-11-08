import SwiftUI

struct SpeechSettingsPage: View {
  @Environment(\.silliesTheme) private var theme
  enum Section: String, CaseIterable, Identifiable {
    case transcription = "Transcription"
    case speakers = "Speaker labels"
    case updates = "Model updates"
    var id: Self { self }
    var title: String {
      switch self {
      case .transcription: String(localized: "Transcription")
      case .speakers: String(localized: "Speaker labels")
      case .updates: String(localized: "Model updates")
      }
    }
  }
  let model: SpeechModelsPresentation
  let activeModelID: String?
  let activeDiarizationModelID: String?
  @State private var section = Section.transcription
  var body: some View {
    Picker("Speech settings", selection: $section) {
      ForEach(Section.allCases) { Text($0.title).tag($0) }
    }.pickerStyle(.segmented)
    switch section {
    case .transcription:
      SpeechModelSettingsView(model: model, activeModelID: activeModelID, scope: .transcription)
    case .speakers:
      SpeechModelSettingsView(
        model: model, activeModelID: activeModelID,
        activeDiarizationModelID: activeDiarizationModelID, scope: .speakers)
    case .updates:
      if let updates = model.updates {
        SettingsCard(title: String(localized: "Keep your downloaded models current")) {
          ModelUpdateSettingsView(model: updates)
        }
      } else {
        Text("Model update checks are unavailable in this build.").foregroundStyle(
          theme.secondary)
      }
    }
  }
}
