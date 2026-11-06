import SwiftUI

struct AudioLanguagePicker: View {
  @Environment(\.silliesTheme) private var theme
  private static let pickerWidth: CGFloat = 270
  private static let guidanceWidth: CGFloat = 320
  let model: AudioSessionPresentation
  @State private var showsGuidance = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Label(
              SpeechLanguageGuidance.title(for: model.model.capabilities.languageControl),
              systemImage: "globe"
            )
            .font(.callout.weight(.semibold))
            Button {
              showsGuidance.toggle()
            } label: {
              Image(systemName: "info.circle").foregroundStyle(theme.secondary)
            }
            .buttonStyle(.plain).accessibilityLabel("Show details")
            .popover(isPresented: $showsGuidance) { guidance }
          }
          Text(model.model.name)
            .font(.caption).foregroundStyle(theme.secondary)
        }
        Spacer(minLength: 8)
        if model.isLoadingLanguages {
          ProgressView().controlSize(.small)
          Text("Checking languages…").font(.callout).foregroundStyle(theme.secondary)
        } else {
          languageMenu
        }
      }
      if model.pendingLanguageID != nil {
        Label(
          model.isPaused
            ? String(localized: "Changing language. Your session stays paused.")
            : String(localized: "Changing language. Audio capture continues."),
          systemImage: "arrow.triangle.2.circlepath"
        )
        .font(.caption).foregroundStyle(theme.accent)
      } else if !model.isLoadingLanguages, !model.languages.contains(where: \.isInstalled) {
        Text(
          model.model.isSystemManaged
            ? String(
              localized:
                "No Apple speech languages are installed. Choose a downloadable model in Settings.")
            : String(
              localized:
                "This model is not installed. Open Settings → Transcription models to download it.")
        )
        .font(.caption).foregroundStyle(theme.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(16).background(theme.card, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.border, lineWidth: 1))
  }

  private var guidance: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(SpeechLanguageGuidance.title(for: model.model.capabilities.languageControl))
        .font(.headline)
      Text(SpeechLanguageGuidance.detail(for: model.model.capabilities.languageControl))
        .font(.callout).foregroundStyle(theme.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }.padding(18).frame(width: Self.guidanceWidth)
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
            ? String(localized: "Apple speech model not installed")
            : String(localized: "Model download required")
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
