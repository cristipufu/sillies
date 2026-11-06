import SilliesCore
import SwiftUI

struct CompanionProfileEditor: View {
  @Environment(\.silliesTheme) private var theme
  let character: CharacterDefinition
  let preferences: CompanionPreferences
  let textModels: TextModelsPresentation
  let voiceModels: VoiceModelsPresentation
  let changed: () -> Void
  @State private var customization: CompanionPreferences.Customization

  init(
    character: CharacterDefinition, preferences: CompanionPreferences,
    textModels: TextModelsPresentation, voiceModels: VoiceModelsPresentation,
    changed: @escaping () -> Void
  ) {
    self.character = character
    self.preferences = preferences
    self.textModels = textModels
    self.voiceModels = voiceModels
    self.changed = changed
    _customization = State(initialValue: preferences.customization(for: character.id))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(
        "Changes apply when your companion is ready. End Talk first to change its language or voice."
      )
      .font(.caption).foregroundStyle(theme.secondary)
      Picker("Conversation language", selection: language) {
        Text("Companion default").tag("")
        ForEach(languageCodes, id: \.self) { code in
          Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code)
        }
      }
      if let voice = voiceModels.manifests.first(where: {
        $0.modelID == voiceModels.selectedModelID
      }) {
        Picker(
          "Voice",
          selection: Binding(
            get: { customization.voices[voice.model.providerID] ?? "" },
            set: { customization.voices[voice.model.providerID] = $0.isEmpty ? nil : $0 }
          )
        ) {
          Text("Companion default").tag("")
          if let savedVoice = customization.voices[voice.model.providerID],
            !voice.model.voices.contains(where: {
              $0.id == savedVoice && $0.supports(language: selectedLanguage)
            })
          {
            Text("Saved voice unavailable for this language").tag(savedVoice)
          }
          ForEach(voice.model.voices.filter { $0.supports(language: selectedLanguage) }) {
            Text($0.name).tag($0.id)
          }
        }
      }
      DisclosureGroup("Advanced") {
        VStack(alignment: .leading, spacing: 12) {
          Picker(
            "Reply model",
            selection: Binding(
              get: { customization.textModelID ?? "" },
              set: { customization.textModelID = $0.isEmpty ? nil : $0 }
            )
          ) {
            Text("Use app default").tag("")
            Text("Apple Intelligence").tag(textModels.fallbackModelID)
            if let saved = customization.textModelID, saved != textModels.fallbackModelID,
              !textModels.manifests.contains(where: { $0.modelID == saved })
            {
              Text("Saved reply model unavailable").tag(saved)
            }
            ForEach(
              textModels.manifests.filter {
                textModels.state(for: $0.modelID) == .downloaded
                  || $0.modelID == customization.textModelID
              }, id: \.modelID
            ) {
              Text($0.model.name).tag($0.modelID)
            }
          }
          Text("Personality").font(.callout.weight(.medium))
          TextEditor(
            text: Binding(
              get: { customization.personality ?? character.chat?.personality ?? "" },
              set: {
                customization.personality = String(
                  $0.prefix(CharacterChatProfile.maximumPersonalityCharacters))
              }
            )
          ).font(.callout).frame(height: 90)
            .padding(8).background(theme.paper, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.border))
          Text("Model performance settings use tested defaults for each model.")
            .font(.caption).foregroundStyle(theme.secondary)
        }.padding(.top, 10)
      }
      HStack {
        Button("Reset to companion defaults") {
          preferences.reset(character)
          customization = preferences.customization(for: character.id)
          changed()
        }.buttonStyle(.plain).foregroundStyle(theme.secondary)
        Spacer()
        Button("Save") {
          preferences.save(customization, for: character)
          changed()
        }.buttonStyle(SoftButtonStyle())
          .disabled(customization == preferences.customization(for: character.id))
      }
      if let error = preferences.error {
        Text(error).font(.caption).foregroundStyle(theme.danger).textSelection(.enabled)
      }
    }
    .onChange(of: preferences.customization(for: character.id)) { old, new in
      // Reconcile external resets without losing unrelated edits still in progress.
      if old.language != new.language { customization.language = new.language }
      if old.personality != new.personality { customization.personality = new.personality }
      if old.voices != new.voices { customization.voices = new.voices }
      if old.textModelID != new.textModelID { customization.textModelID = new.textModelID }
    }
  }

  private var selectedLanguage: String {
    customization.language ?? character.chat?.languageIdentifier ?? "en"
  }
  private var language: Binding<String> {
    Binding(
      get: { customization.language ?? "" },
      set: { customization.language = $0.isEmpty ? nil : $0 })
  }
  private var languageCodes: [String] {
    let codes = Set(
      Locale.LanguageCode.isoLanguageCodes.map(\.identifier)
        + [selectedLanguage])
    return codes.sorted {
      (Locale.current.localizedString(forLanguageCode: $0) ?? $0).localizedStandardCompare(
        Locale.current.localizedString(forLanguageCode: $1) ?? $1) == .orderedAscending
    }
  }
}
