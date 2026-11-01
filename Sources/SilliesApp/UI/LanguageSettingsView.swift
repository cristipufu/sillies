import SwiftUI

struct LanguageSettingsView: View {
  @Environment(\.silliesTheme) private var theme
  @Bindable var model: LanguagePreferences
  var body: some View {
    SettingsCard(
      title: String(localized: "Language"),
      detail: String(localized: "Choose the language for Sillies menus and controls.")
    ) {
      Picker("App language", selection: Binding(get: { model.selectedID }, set: model.select)) {
        Text("System language").tag(LanguagePreferences.systemID)
        ForEach(model.languages) { language in
          Text(verbatim: language.language).tag(language.code)
        }
      }.disabled(model.languages.isEmpty)
      if model.requiresRestart {
        Label(
          "Your choice takes effect the next time Sillies opens.", systemImage: "arrow.clockwise"
        )
        .font(.caption).foregroundStyle(theme.secondary)
      }
      Text("Speech recognition and companion languages have their own settings.")
        .font(.caption).foregroundStyle(theme.secondary)
      if let error = model.error {
        Text(error).foregroundStyle(theme.danger).textSelection(.enabled)
      }
    }.onAppear { model.start() }
  }
}
