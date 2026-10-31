import SilliesModelStore
import SwiftUI

struct VoiceModelSettingsView: View {
  let model: VoiceModelsPresentation

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      SettingsCard(
        title: "A little voice. A lot of personality.",
        detail:
          "Choose a local voice model for Chat. Each companion has its own preferred voice and personality."
      ) {
        Label("Your conversations stay on this Mac.", systemImage: "lock.shield")
        Text(
          "Download a model, then choose Use for Chat. First use takes longer while the voice loads. Speech & Meetings controls how Sillies listens; Local AI controls its replies."
        )
        .foregroundStyle(SilliesTheme.secondary)
        Text("Each model lists its supported languages and voice options below.")
          .font(.caption).foregroundStyle(SilliesTheme.secondary)
        if model.selectedModelID == VoiceModelEnvironment.disabledID {
          Label("Text replies only", systemImage: "text.bubble").foregroundStyle(
            SilliesTheme.accent)
        } else {
          Button("Use text replies only") { model.select(VoiceModelEnvironment.disabledID) }
            .buttonStyle(SoftButtonStyle()).disabled(model.activeID != nil)
        }
      }
      if model.isLoading { ProgressView("Checking installed voices…") }
      ForEach(model.manifests, id: \.modelID) { manifest in card(manifest) }
      if let error = model.error {
        Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
      }
    }.task { await model.load() }
  }

  private func card(_ manifest: TTSModelManifest) -> some View {
    let state = model.state(for: manifest.modelID)
    return SettingsCard(title: manifest.model.name, detail: manifest.model.detail) {
      DisclosureGroup("Supported languages (\(manifest.model.languages.count))") {
        Text(
          manifest.model.languages.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .joined(separator: " · ")
        )
        .font(.caption).foregroundStyle(SilliesTheme.secondary)
      }
      Text(manifest.model.license).font(.caption).foregroundStyle(SilliesTheme.secondary)
      Text(
        "\(ByteCountFormatter.string(fromByteCount: manifest.downloadBytes, countStyle: .file)) download · \(manifest.model.minimumMemoryGB) GB memory required"
      )
      .font(.caption).foregroundStyle(SilliesTheme.secondary)
      if !model.supports(manifest) {
        Label("This Mac has less memory than this model requires.", systemImage: "memorychip").font(
          .caption)
      }
      if let fraction = state.downloadFraction {
        ProgressView(value: fraction).tint(SilliesTheme.accent)
      }
      Text(state.label).font(.caption).foregroundStyle(SilliesTheme.secondary).textSelection(
        .enabled)
      HStack {
        actions(manifest, state: state)
        Spacer(minLength: 0)
        Link("Model & license ↗", destination: manifest.model.sourceURL).font(.caption)
      }
    }
  }

  @ViewBuilder private func actions(_ manifest: TTSModelManifest, state: ModelInstallationState)
    -> some View
  {
    switch state {
    case .downloaded, .ready:
      if model.selectedModelID == manifest.modelID {
        Label("Selected", systemImage: "checkmark.circle.fill").foregroundStyle(SilliesTheme.accent)
      } else {
        Button("Use for Chat") { model.select(manifest.modelID) }
          .buttonStyle(SoftButtonStyle()).disabled(model.activeID != nil)
      }
      Button("Remove", role: .destructive) { model.remove(manifest) }
        .buttonStyle(SoftButtonStyle()).disabled(model.activeID != nil)
    case .downloading, .verifying:
      Button("Pause download") { model.pauseDownload() }.buttonStyle(SoftButtonStyle())
    case .cancelling: ProgressView().controlSize(.small)
    default:
      Button(state == .paused ? "Resume download" : "Download") { model.download(manifest) }
        .buttonStyle(SoftButtonStyle()).disabled(model.activeID != nil || !model.supports(manifest))
    }
  }
}
