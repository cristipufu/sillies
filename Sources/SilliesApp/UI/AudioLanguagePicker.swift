import SwiftUI

struct AudioLanguagePicker: View {
  private static let pickerWidth: CGFloat = 270
  let model: AudioSessionPresentation

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Label("Spoken language", systemImage: "globe")
            .font(.callout.weight(.semibold))
          Text(model.model.name)
            .font(.caption).foregroundStyle(SilliesTheme.secondary)
        }
        Spacer(minLength: 8)
        if model.isLoadingLanguages {
          ProgressView().controlSize(.small)
          Text("Checking languages…").font(.callout).foregroundStyle(SilliesTheme.secondary)
        } else {
          languageMenu
        }
      }
      if model.pendingLanguageID != nil {
        Label(
          model.isPaused
            ? "Changing language. Your session stays paused."
            : "Changing language. Audio capture continues.",
          systemImage: "arrow.triangle.2.circlepath"
        )
        .font(.caption).foregroundStyle(SilliesTheme.accent)
      } else if !model.isLoadingLanguages, !model.languages.contains(where: \.isInstalled) {
        Text(
          model.model.isSystemManaged
            ? "No Apple speech languages are installed. Choose a downloadable model in Settings."
            : "This model is not installed. Open Settings → Transcription models to download it."
        )
        .font(.caption).foregroundStyle(SilliesTheme.secondary)
        .fixedSize(horizontal: false, vertical: true)
      } else {
        Text(
          model.model.capabilities.languageControl == .automatic
            ? "Detects the spoken language automatically, including English and Romanian."
            : "Language changes apply to new speech. Model changes in Settings apply to the next session."
        )
        .font(.caption).foregroundStyle(SilliesTheme.secondary)
      }
      if let notice = model.reasoningNotice {
        Text(notice).font(.caption).foregroundStyle(SilliesTheme.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(16).background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(SilliesTheme.border, lineWidth: 1))
  }

  private var languageMenu: some View {
    Picker(
      "Spoken language",
      selection: Binding(
        get: { model.pendingLanguageID ?? model.selectedLanguageID ?? "" },
        set: { model.onSelectLanguage?($0) }
      )
    ) {
      if model.selectedLanguageID == nil { Text("Choose a language").tag("") }
      Section("Ready on this Mac") {
        ForEach(model.languages.filter(\.isInstalled)) { language in
          Text(language.name).tag(language.id)
        }
      }
      let unavailable = model.languages.filter { !$0.isInstalled }
      if !unavailable.isEmpty {
        Section(
          model.model.isSystemManaged
            ? "Apple speech model not installed" : "Model download required"
        ) {
          ForEach(unavailable) { language in
            Text(language.name).tag(language.id).disabled(true)
          }
        }
      }
    }
    .labelsHidden().pickerStyle(.menu).controlSize(.large)
    .frame(width: Self.pickerWidth)
    .disabled(!model.canSelectLanguage)
    .accessibilityLabel("Spoken language")
    .accessibilityHint("Changes apply to new speech. Earlier transcript is preserved.")
  }

}
