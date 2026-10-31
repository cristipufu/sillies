import SilliesCore
import SilliesSpeech
import SwiftUI

struct DictationSettingsView: View {
  let tools: WritingTools
  @State private var phrase = ""
  @State private var heardAs = ""
  @State private var languages: [SpeechLanguage] = []
  @State private var languageError: String?
  var body: some View {
    @Bindable var preferences = tools.dictation.preferences
    VStack(alignment: .leading, spacing: 12) {
      Text(
        "Assign Hold to dictate or Start / finish dictation above. Focus a text field, then use your shortcut. Escape is never intercepted from other apps; use Cancel in the indicator or assign its own shortcut."
      )
      .font(.caption).foregroundStyle(SilliesTheme.secondary)
      Picker("Output", selection: $preferences.style) {
        ForEach(DictationOutputStyle.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      Picker("Language", selection: $preferences.languageIdentifier) {
        Text("Automatic / device language").tag("auto")
        ForEach(languages.filter { !$0.isAutomatic }) { Text($0.name).tag($0.id) }
      }
      if let languageError { Text(languageError).foregroundStyle(.red).font(.caption) }
      Text(
        "Uses the transcription model selected below. English/Romanian mixing works best with automatic detection on a multilingual model. If local cleanup is unavailable or late, the transcript is used. Each dictation finishes after five minutes."
      )
      .font(.caption).foregroundStyle(SilliesTheme.secondary)
      Button("Open recovery history") { tools.openHistory() }
      Button("Enable text insertion access…") { tools.enableInsertionAccess() }
      Text(
        "Accessibility is required only for inserting text. Dictation can still produce text to copy without it."
      )
      .font(.caption).foregroundStyle(SilliesTheme.secondary)
      if let latency = tools.dictation.releaseToInsertion {
        Text("Last release to insertion: \(latency, specifier: "%.2f") seconds")
          .font(.caption).foregroundStyle(SilliesTheme.secondary)
      }
      Picker("Translate selections into", selection: $preferences.translationLanguage) {
        Text("English").tag("en")
        Text("Romanian").tag("ro")
      }
      Text(
        "Selection commands require a language supported by Apple’s on-device writing model. Unsupported languages keep their original text."
      )
      .font(.caption).foregroundStyle(SilliesTheme.secondary)
      Divider()
      Text("Personal dictionary").fontWeight(.semibold)
      Text(
        "Names and technical terms guide supported engines. Optional “heard as” phrases are replaced as whole words for every engine."
      )
      .font(.caption).foregroundStyle(SilliesTheme.secondary)
      TextField("Preferred spelling, e.g. Ștefănescu", text: $phrase)
      TextField("Heard as (optional)", text: $heardAs)
      Button("Add word or phrase") {
        tools.vocabulary.add(phrase: phrase, heardAs: heardAs)
        if tools.vocabulary.error == nil {
          phrase = ""
          heardAs = ""
        }
      }.disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      if let error = tools.vocabulary.error { Text(error).font(.caption).foregroundStyle(.red) }
      ForEach(tools.vocabulary.entries) { entry in
        HStack {
          Text(entry.heardAs.isEmpty ? entry.phrase : "\(entry.heardAs) → \(entry.phrase)")
          Spacer()
          Button {
            tools.vocabulary.remove(entry.id)
          } label: {
            Image(systemName: "minus.circle")
          }
          .accessibilityLabel("Remove \(entry.phrase)")
        }
      }
    }.task(id: tools.modelID) {
      do {
        let catalog = try await tools.languages.load()
        languages = catalog.installed
        let selected = tools.dictation.preferences.languageIdentifier
        if selected != "auto", let language = catalog.installedLanguage(matching: selected) {
          tools.dictation.preferences.languageIdentifier = language.id
        }
        languageError = nil
      } catch {
        languageError = error.localizedDescription
      }
    }
  }
}
