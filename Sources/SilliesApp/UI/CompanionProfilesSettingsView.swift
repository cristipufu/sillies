import SilliesCore
import SwiftUI

struct CompanionProfilesSettingsView: View {
  let characters: [CharacterDefinition]
  let preferences: CompanionPreferences
  let textModels: TextModelsPresentation
  let voiceModels: VoiceModelsPresentation
  @State private var selectedID = ""

  var body: some View {
    SettingsCard(title: String(localized: "A voice of their own")) {
      Picker("Companion", selection: $selectedID) {
        ForEach(characters.filter { $0.chat != nil }) { Text($0.name).tag($0.id) }
      }
      if let character = characters.first(where: { $0.id == selectedID }) {
        CompanionProfileEditor(
          character: character, preferences: preferences, textModels: textModels,
          voiceModels: voiceModels, changed: {}
        ).id(character.id)
      }
    }.onAppear {
      if selectedID.isEmpty { selectedID = characters.first(where: { $0.chat != nil })?.id ?? "" }
    }
  }
}
