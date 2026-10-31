import SwiftUI

struct SpeechSettingsPage: View {
  enum Section: String, CaseIterable, Identifiable {
    case transcription = "Transcription"
    case speakers = "Speaker labels"
    case updates = "Model updates"
    var id: Self { self }
  }
  let model: SpeechModelsPresentation
  let activeModelID: String?
  let activeDiarizationModelID: String?
  @State private var section = Section.transcription
  var body: some View {
    Picker("Speech settings", selection: $section) {
      ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
    }.pickerStyle(.segmented)
    switch section {
    case .transcription:
      SettingsCard(
        title: "Turn speech into words",
        detail:
          "The selected model is shared by dictation, Listen, Participate, and Record. Changes apply to your next session."
      ) {
        SpeechModelSettingsView(model: model, activeModelID: activeModelID, scope: .transcription)
      }
    case .speakers:
      SettingsCard(
        title: "Who said what?",
        detail:
          "Optional speaker detection separates voices in meetings. It doesn’t identify people by name."
      ) {
        SpeechModelSettingsView(
          model: model, activeModelID: activeModelID,
          activeDiarizationModelID: activeDiarizationModelID, scope: .speakers)
      }
    case .updates:
      if let updates = model.updates {
        SettingsCard(title: "Keep your downloaded models current") {
          ModelUpdateSettingsView(model: updates)
        }
      } else {
        Text("Model update checks are unavailable in this build.").foregroundStyle(
          SilliesTheme.secondary)
      }
    }
  }
}
