import AppKit
import SilliesCore
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func setupStepsAndMissingCapabilitiesFitBothThemesWithoutPresentation()
  async throws
{
  let fixture = try SetupFixture(
    reply: .init(notice: "Choose an installed reply model to start a conversation."),
    voice: .init(notice: "Choose a voice that supports the conversation language."))
  defer { fixture.close() }
  fixture.permissions.granted.withLock { $0 = false }
  let model = fixture.makePresentation()
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(fixture.domain)
  defer {
    removeTestFile(at: root)
    model.stop()
  }
  let text = TextModelsPresentation()
  let voices = try VoiceServices(
    defaults: fixture.defaults, directory: root.appendingPathComponent("voices"))
  let speech = try SpeechServices(
    defaults: fixture.defaults, modelDirectory: root.appendingPathComponent("speech"))
  defer {
    text.stop()
    voices.models.stop()
    speech.stop()
  }
  await text.load()
  await voices.models.load()
  await speech.models.load()
  let suggestions = SetupModelSuggestions(text: text, voice: voices.models, speech: speech.models)
  await suggestions.load()
  #expect(!suggestions.evidence.isEmpty)
  #expect(suggestions.error == nil)
  model.chooseActivity(.talk)
  try await awaitSetup { !model.isChecking }
  let registry = RendererRegistry()
  for scheme in [ColorScheme.light, .dark] {
    for step in SetupJourney.Step.allCases {
      model.journey.move(to: step)
      try renderSkillInterface(
        SetupView(
          model: model, registry: registry, textModels: text, voiceModels: voices.models,
          suggestions: suggestions
        ).environment(\.colorScheme, scheme),
        size: CGSize(width: 620, height: 620),
        name: "sillies-setup-\(step.rawValue)-\(scheme)")
    }
  }
  await fixture.reply.setNotice(nil)
  await fixture.voice.setNotice(nil)
  fixture.permissions.granted.withLock { $0 = true }
  model.refresh()
  try await awaitSetup { !model.isChecking }
  #expect(model.canContinue)
  for scheme in [ColorScheme.light, .dark] {
    try renderSkillInterface(
      SetupView(
        model: model, registry: registry, textModels: text,
        voiceModels: voices.models, suggestions: suggestions
      ).environment(\.colorScheme, scheme),
      size: CGSize(width: 620, height: 620), name: "sillies-setup-ready-\(scheme)")
    try renderSkillInterface(
      CompanionProfileEditor(
        character: fixture.characters[0], preferences: fixture.preferences,
        textModels: text, voiceModels: voices.models, changed: {}
      ).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SilliesTheme().paper).foregroundStyle(SilliesTheme().ink)
        .environment(\.colorScheme, scheme),
      size: CGSize(width: 620, height: 360), name: "sillies-companion-profile-\(scheme)")
  }
  #expect(fixture.capture.starts.withLock { $0 } == 0)
  #expect(await fixture.voice.starts == 0)
}

@Test @MainActor func setupRecommendationsRespectWholeWorkflowMemoryAndVoiceLanguage() async throws
{
  let fixture = try SetupFixture()
  defer { fixture.close() }
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(fixture.domain)
  defer { removeTestFile(at: root) }
  let text = TextModelsPresentation()
  let voices = try VoiceServices(
    defaults: fixture.defaults, directory: root.appendingPathComponent("voices"))
  let speech = try SpeechServices(
    defaults: fixture.defaults, modelDirectory: root.appendingPathComponent("speech"))
  defer {
    text.stop()
    voices.models.stop()
    speech.stop()
  }
  await text.load()
  await voices.models.load()
  await speech.models.load()
  let small = SetupModelSuggestions(
    text: text, voice: voices.models, speech: speech.models, physicalMemory: 8 * 1_073_741_824)
  await small.load()
  let chat = try #require(small.suggestedText(activity: .chat, language: "en"))
  #expect(chat.model.minimumMemoryGB <= 8)
  if let talk = small.suggestedText(activity: .talk, language: "en") {
    #expect(talk.downloadBytes <= chat.downloadBytes)
  }
  #expect(small.suggestedVoice(language: "unsupported-language") == nil)
  #expect(small.suggestedVoice(language: "fr")?.model.supports(language: "fr") == true)
  let insufficient = SetupModelSuggestions(
    text: text, voice: voices.models, speech: speech.models, physicalMemory: 2 * 1_073_741_824)
  #expect(insufficient.suggestedText(activity: .chat, language: "en") == nil)
  #expect(insufficient.suggestedVoice(language: "fr") == nil)
}
