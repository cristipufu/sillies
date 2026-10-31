import SilliesCore
import SilliesSpeech
import SwiftUI

struct DictationSettingsView: View {
  let tools: WritingTools
  var hasInsertionAccess = false
  var shortcuts: CommandShortcuts? = nil
  var openShortcuts: () -> Void = {}
  var openSpeech: () -> Void = {}
  @State private var languages: [SpeechLanguage] = []
  @State private var languageError: String?
  @State private var languageControl = SpeechModelDescriptor.Capabilities.LanguageControl.selectable

  var body: some View {
    @Bindable var preferences = tools.preferences
    VStack(alignment: .leading, spacing: 22) {
      SettingsCard(
        title: "Speak. Finish. It’s there.",
        detail:
          "Focus a text field, then use a shortcut. An available mascot listens and inserts your words when you finish."
      ) {
        shortcut(.holdDictation, title: "Hold to speak")
        shortcut(.toggleDictation, title: "Press to start / finish")
        Button("Change shortcuts…", action: openShortcuts).buttonStyle(SoftButtonStyle())
        if hasInsertionAccess {
          Label("Text insertion is enabled", systemImage: "checkmark.circle.fill")
            .font(.caption).foregroundStyle(SilliesTheme.accent)
        } else {
          SessionFailureNotice(failure: .permissionDenied(.openAccessibilitySettings))
        }
      }
      SettingsCard(title: "Your words, your way") {
        Picker("Output", selection: $preferences.style) {
          ForEach(DictationOutputStyle.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Text(
          preferences.style == .verbatim
            ? "Keep the recognized words as they are."
            : "Lightly tidy punctuation and filler words. Names, numbers, and meaning stay yours."
        )
        .font(.caption).foregroundStyle(SilliesTheme.secondary)
        Divider()
        Picker(
          SpeechLanguageGuidance.title(for: languageControl),
          selection: $preferences.languageIdentifier
        ) {
          Text("Automatic / device language").tag("auto")
          ForEach(languages.filter { !$0.isAutomatic }) { Text($0.name).tag($0.id) }
        }
        if let languageError { Text(languageError).foregroundStyle(.red).font(.caption) }
        Text(
          languageControl == .hinted
            ? SpeechLanguageGuidance.detail(for: languageControl)
            : "Mixing English and Romanian? Use automatic detection with a multilingual model."
        )
        .font(.caption).foregroundStyle(SilliesTheme.secondary)
        Button("Choose a speech model…", action: openSpeech).buttonStyle(.link)
        Divider()
        PersonalDictionarySettings(model: tools.vocabulary)
      }
      SettingsCard(
        title: "Edit a selection",
        detail:
          "Select text in another app, then use Shorten, Fix grammar, or Translate from a shortcut."
      ) {
        Picker("Translate into", selection: $preferences.translationLanguage) {
          Text("English").tag("en")
          Text("Romanian").tag("ro")
        }
        Text(
          "Uses Apple’s on-device writing model. If the language isn’t supported, your original text stays intact."
        )
        .font(.caption).foregroundStyle(SilliesTheme.secondary)
        Button("Set up selection shortcuts…", action: openShortcuts).buttonStyle(.link)
      }
      SettingsCard(
        title: "Your words won’t get lost",
        detail:
          "The last 20 dictations and edits stay in Recent writing. Copy a result or delete it whenever you like. Audio isn’t saved."
      ) {
        Button("Open Recent writing", systemImage: "text.bubble") { tools.openHistory() }
          .buttonStyle(SoftButtonStyle())
        DisclosureGroup("How dictation finishes") {
          Text(
            "Each dictation finishes after five minutes. If cleanup is unavailable or takes too long, Sillies uses the transcript. If the destination changes, the result stays ready to copy."
          )
          .font(.caption).foregroundStyle(SilliesTheme.secondary).padding(.top, 8)
          if let latency = tools.dictation.releaseToInsertion {
            Text("Last finish to insertion: \(latency, specifier: "%.2f") seconds")
              .font(.caption).foregroundStyle(SilliesTheme.secondary)
          }
        }.font(.caption)
      }
    }
    .task(id: tools.modelID) { await loadLanguages() }
  }

  private func shortcut(_ command: AppCommand, title: String) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(shortcuts?.bindings[command.rawValue]?.display ?? "Not assigned")
        .font(.system(.callout, design: .rounded).weight(.semibold))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(SilliesTheme.soft, in: RoundedRectangle(cornerRadius: 6))
    }
  }

  private func loadLanguages() async {
    do {
      let catalog = try await tools.languages.load()
      languages = catalog.installed
      languageControl = catalog.model.capabilities.languageControl
      let selected = tools.preferences.languageIdentifier
      if selected != "auto", let language = catalog.installedLanguage(matching: selected) {
        tools.preferences.languageIdentifier = language.id
      }
      languageError = nil
    } catch { languageError = error.localizedDescription }
  }
}
