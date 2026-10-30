import SilliesCore
import SilliesModelStore
import SwiftUI

struct SpeechModelSettingsView: View {
  let model: SpeechModelsPresentation
  let activeModelID: String?
  var activeDiarizationModelID: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Apple Speech").fontWeight(.semibold)
          Text("Uses languages installed by macOS.").font(.caption).foregroundStyle(
            SilliesTheme.secondary)
        }
        Spacer()
        if model.selectedModelID == SpeechModelDescriptor.apple.id {
          selectedLabel
        } else {
          Button("Use") { model.useApple() }.buttonStyle(SoftButtonStyle())
        }
      }
      ForEach(model.manifests, id: \.model.id) { manifest in
        Divider()
        modelRow(manifest)
      }
      if model.isLoading { ProgressView("Checking models…").controlSize(.small) }
      if let updates = model.updates {
        Divider()
        ModelUpdateSettingsView(model: updates)
      }
      if let error = model.error {
        Text(error).font(.caption).foregroundStyle(.red).fixedSize(
          horizontal: false, vertical: true)
      }
      Text(
        "Changes apply to your next session. Downloads need internet; your audio and transcripts stay on this Mac."
      )
      .font(.caption).foregroundStyle(SilliesTheme.secondary).fixedSize(
        horizontal: false, vertical: true)
    }
    .task { await model.load() }
  }

  private var selectedLabel: some View {
    Label("Selected", systemImage: "checkmark.circle.fill")
      .font(.caption.weight(.medium)).foregroundStyle(SilliesTheme.accent)
  }

  private func modelRow(_ manifest: SpeechModelManifest) -> some View {
    let state = model.state(for: manifest.model.id)
    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(manifest.model.name).fontWeight(.semibold)
          Text(
            ByteCountFormatter.string(fromByteCount: manifest.downloadBytes, countStyle: .file)
              + (manifest.model.isDiarizationModel
                ? " download · Speaker detection"
                : " download · \(manifest.model.capabilities.languages.count) languages")
          )
          .font(.caption).foregroundStyle(SilliesTheme.secondary)
        }
        Spacer(minLength: 8)
        if model.isSelected(manifest) { selectedLabel }
      }
      Text(manifest.model.detail).font(.caption).foregroundStyle(SilliesTheme.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if case .downloading(let fraction) = state {
        ProgressView(value: fraction).accessibilityLabel("Model download")
      }
      HStack(spacing: 10) {
        if state == .preparing || state == .verifying || state == .validating {
          ProgressView().controlSize(.small)
        }
        Text(state.label).font(.caption).foregroundStyle(SilliesTheme.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        actions(manifest, state: state)
      }
      if state == .preparing {
        Text("The first preparation can take longer. You can keep using Sillies.")
          .font(.caption).foregroundStyle(SilliesTheme.secondary)
      }
      if isInUse(manifest) {
        Text("In use by your current session.").font(.caption).foregroundStyle(SilliesTheme.accent)
      }
      if state == .downloaded || state == .ready {
        updateActions(manifest)
      }
      DisclosureGroup(
        manifest.model.isDiarizationModel ? "About speaker labels" : "Languages & license"
      ) {
        VStack(alignment: .leading, spacing: 6) {
          if manifest.model.isDiarizationModel {
            Text(
              "Speaker numbers are local to each audio source and meeting. Names are not inferred. Overlapping or uncertain speech is marked explicitly; labels can be wrong."
            )
          } else {
            Text(
              manifest.model.capabilities.languages.map {
                Locale.current.localizedString(forLanguageCode: $0) ?? $0
              }.joined(separator: ", "))
          }
          Text(manifest.model.license)
          Text("Installed revision: \(manifest.model.revision.prefix(20))")
          if let url = URL(string: manifest.model.sourceURL) {
            Link("Model information", destination: url)
          }
        }.font(.caption).foregroundStyle(SilliesTheme.secondary)
      }.font(.caption)
    }
  }

  @ViewBuilder
  private func actions(_ manifest: SpeechModelManifest, state: SpeechModelsPresentation.State)
    -> some View
  {
    #if arch(arm64)
      switch state {
      case .downloading, .verifying:
        Button("Pause") { model.pause(manifest.model.id) }.buttonStyle(SoftButtonStyle())
      case .preparing, .validating:
        Button("Cancel") { model.pause(manifest.model.id) }.buttonStyle(SoftButtonStyle())
      case .downloaded, .ready:
        if !model.isSelected(manifest) {
          Button(manifest.model.isDiarizationModel ? "Enable" : "Use") { model.use(manifest) }
            .buttonStyle(SoftButtonStyle())
        } else if manifest.model.isDiarizationModel {
          Button("Disable") { model.disableSpeakerDetection() }.buttonStyle(SoftButtonStyle())
        }
        removeButton(manifest)
      case .preparationFailed:
        Button("Retry preparation") { model.retryPreparation(manifest) }.buttonStyle(
          SoftButtonStyle())
        removeButton(manifest)
      case .absent, .paused, .failed:
        Button(state == .absent ? "Download" : "Retry download") { model.download(manifest) }
          .buttonStyle(SoftButtonStyle())
      case .cancelling:
        ProgressView().controlSize(.small)
      }
    #else
      Text("Requires Apple Silicon").font(.caption)
    #endif
  }

  @ViewBuilder private func updateActions(_ manifest: SpeechModelManifest) -> some View {
    if let candidate = model.update(for: manifest) {
      VStack(alignment: .leading, spacing: 6) {
        Label("Model update available", systemImage: "arrow.down.circle")
          .font(.caption.weight(.semibold)).foregroundStyle(SilliesTheme.accent)
        Text(
          "Compatibility is checked before switching. Your current version is kept for rollback."
        )
        .font(.caption).foregroundStyle(SilliesTheme.secondary)
        Button(
          "Download & check update (\(ByteCountFormatter.string(fromByteCount: candidate.downloadBytes, countStyle: .file)))"
        ) {
          model.installUpdate(candidate)
        }.buttonStyle(SoftButtonStyle()).disabled(isInUse(manifest))
      }
    }
    if model.rollbackModelIDs.contains(manifest.model.id) {
      Button("Use previous version") { model.rollBack(manifest) }
        .font(.caption).buttonStyle(.borderless).disabled(isInUse(manifest))
    }
    if let notice = model.updates?.snapshot.entries[manifest.model.id]?.notice {
      Text(notice).font(.caption).foregroundStyle(SilliesTheme.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func removeButton(_ manifest: SpeechModelManifest) -> some View {
    Button(model.selectedModelID == manifest.model.id ? "Remove & use Apple" : "Remove") {
      model.remove(manifest)
    }
    .buttonStyle(.borderless).disabled(isInUse(manifest))
  }

  private func isInUse(_ manifest: SpeechModelManifest) -> Bool {
    manifest.model.id == activeModelID || manifest.model.id == activeDiarizationModelID
  }
}
