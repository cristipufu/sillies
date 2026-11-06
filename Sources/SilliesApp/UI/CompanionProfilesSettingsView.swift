import SilliesCore
import SwiftUI

struct CompanionProfilesSettingsView: View {
  let characters: [CharacterDefinition]
  let preferences: CompanionPreferences
  let textModels: TextModelsPresentation
  let voiceModels: VoiceModelsPresentation
  @Binding var selectedID: String
  var openMemories: ((String) -> Void)?

  var body: some View {
    SettingsCard(title: String(localized: "A voice of their own")) {
      Picker("Companion", selection: $selectedID) {
        ForEach(characters.filter { $0.chat != nil }) { Text($0.name).tag($0.id) }
      }
      if let character = characters.first(where: { $0.id == selectedID }) {
        if let openMemories {
          Button("Memories", systemImage: "brain.head.profile") { openMemories(character.id) }
            .buttonStyle(SoftButtonStyle())
        }
        CompanionProfileEditor(
          character: character, preferences: preferences, textModels: textModels,
          voiceModels: voiceModels, changed: {}
        ).id(character.id)
      }
    }.onAppear {
      if !characters.contains(where: { $0.id == selectedID && $0.chat != nil }) {
        selectedID = characters.first(where: { $0.chat != nil })?.id ?? ""
      }
    }.task {
      await textModels.load()
      await voiceModels.load()
    }
  }
}
