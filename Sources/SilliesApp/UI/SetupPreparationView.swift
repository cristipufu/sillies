import SwiftUI

struct SetupPreparationView: View {
  @Environment(\.silliesTheme) private var theme
  let model: SetupPresentation
  let textModels: TextModelsPresentation
  let voiceModels: VoiceModelsPresentation
  let suggestions: SetupModelSuggestions
  @State private var previewText = String(localized: "Hello! It’s nice to meet you.")

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text(model.journey.activity.title)
            .font(.system(.title2, design: .rounded).weight(.bold))
          Text(model.journey.activity.detail).font(.callout).foregroundStyle(theme.secondary)
        }
        Spacer(minLength: 12)
        if model.isChecking { ProgressView().controlSize(.small) }
      }
      if let failure = model.failure { SessionFailureNotice(failure: failure) }
      if model.journey.activity != .companions {
        VStack(spacing: 0) {
          ForEach(model.requirements) { requirement in
            requirementRow(requirement)
            if requirement.id != model.requirements.last?.id { Divider().padding(.horizontal, 16) }
          }
          if model.isChecking && model.requirements.isEmpty {
            ProgressView("Checking your setup…").padding(22).frame(maxWidth: .infinity)
          }
        }.background(theme.card, in: RoundedRectangle(cornerRadius: 15))
          .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(theme.border, lineWidth: 0.8))
        SetupModelSuggestionsView(
          model: suggestions, activity: model.journey.activity,
          language: model.profile?.languageIdentifier ?? "en",
          overrideID: model.replyModelOverride,
          refresh: model.refresh)
        if model.journey.activity == .talk || model.journey.activity == .meetings {
          audioTrial
        }
        if let character = model.character {
          if model.replyModelOverride != nil {
            Button("Use app default", action: model.useDefaultReplyModel).buttonStyle(
              SoftButtonStyle())
          }
          DisclosureGroup(
            "Personalize your companion",
            isExpanded: Binding(
              get: { model.isProfileExpanded }, set: { model.isProfileExpanded = $0 })
          ) {
            CompanionProfileEditor(
              character: character, preferences: model.profiles,
              textModels: textModels, voiceModels: voiceModels, changed: model.refresh
            )
            .padding(.top, 12).id(character.id)
          }.font(.callout.weight(.medium)).id(SetupView.Section.profile)
        }
      }
      discovery
    }
  }

  private func requirementRow(_ requirement: SetupRequirement) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: requirement.state == .ready ? "checkmark.circle.fill" : "circle.dotted")
        .font(.title3).foregroundStyle(
          requirement.state == .ready ? theme.success : theme.secondary
        )
        .padding(.top, 1)
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(requirement.title).font(.callout.weight(.semibold))
          if requirement.isOptional {
            Text("Optional").font(.caption).foregroundStyle(theme.secondary)
          }
        }
        Text(requirement.detail).font(.caption).foregroundStyle(theme.secondary)
          .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
      }
      Spacer(minLength: 8)
      Button(
        requirement.state == .ready ? String(localized: "Change") : String(localized: "Set up")
      ) {
        model.resolve(requirement)
      }.buttonStyle(SoftButtonStyle()).font(.caption)
    }.padding(16)
  }

  private var audioTrial: some View {
    SettingsCard(
      title: String(localized: "Try it before you start"),
      detail: String(localized: "A quick check. Nothing from this test is saved.")
    ) {
      HStack(spacing: 12) {
        if model.audio.phase == .idle {
          Button("Test microphone", systemImage: "mic") { model.testMicrophone() }
            .buttonStyle(SoftButtonStyle())
            .disabled(!hasReady(.microphone) || !hasReady(.recognition))
          if model.journey.activity == .talk {
            Button("Preview voice", systemImage: "speaker.wave.2") {
              model.testVoice(text: previewText)
            }
            .buttonStyle(SoftButtonStyle()).disabled(!hasReady(.voice))
          }
        } else {
          Button("Stop", systemImage: "stop.fill", action: model.audio.stop)
            .buttonStyle(SoftButtonStyle()).disabled(model.audio.phase == .stopping)
          if model.audio.phase == .microphone {
            ProgressView(value: model.audio.level).tint(theme.accent)
              .accessibilityLabel("Microphone level")
          } else {
            ProgressView().controlSize(.small)
          }
        }
      }
      if model.journey.activity == .talk {
        TextField("Preview text", text: $previewText, axis: .vertical)
          .textFieldStyle(.roundedBorder).lineLimit(1...3)
      }
      if !model.audio.transcript.isEmpty {
        Text(model.audio.transcript).font(.callout).textSelection(.enabled)
      }
      if model.audio.heardVoice {
        Label("Voice preview complete", systemImage: "checkmark.circle")
          .font(.caption).foregroundStyle(theme.success)
      }
      if let attribution = model.audio.voiceAttribution {
        ModelAttributionLink(attribution: attribution)
      }
      if let failure = model.audio.failure {
        SessionWarningNotice(message: failure) {}
      }
    }
  }

  private var discovery: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Your companion, two ways", systemImage: "sparkles")
        .font(.callout.weight(.semibold))
      Text("Double-click a companion for Chat or Talk.")
      Text("Drag a companion onto a window for Listen, Participate and other window skills.")
      if model.journey.activity == .meetings {
        Text(
          "When your meeting starts, drag your companion onto its window and choose Listen or Participate. Recording starts only when you choose it."
        )
      }
    }.font(.callout).foregroundStyle(theme.secondary).padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(theme.soft.opacity(0.6), in: RoundedRectangle(cornerRadius: 15))
  }

  private func hasReady(_ id: SetupRequirement.ID) -> Bool {
    model.requirements.contains { $0.id == id && $0.state == .ready }
  }
}
