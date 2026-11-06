import SilliesModelStore
import SwiftUI

/// One set of installation actions for model catalogs and guided setup.
struct ModelInstallationControls<Manifest: ModelArtifactManifest>: View {
  enum Scope { case choose, manage }
  @Environment(\.silliesTheme) private var theme
  let model: DownloadableModelsPresentation<Manifest>
  let manifest: Manifest
  let selectionTitle: String
  let scope: Scope

  var body: some View {
    switch model.state(for: manifest.modelID) {
    case .downloaded, .ready:
      if model.selectedModelID == manifest.modelID {
        Label("Selected", systemImage: "checkmark.circle.fill").foregroundStyle(theme.accent)
      } else {
        Button(selectionTitle) { model.select(manifest.modelID) }
          .buttonStyle(SoftButtonStyle()).disabled(model.activeID != nil)
      }
      if scope == .manage {
        Button("Remove", role: .destructive) { model.remove(manifest) }
          .buttonStyle(SoftButtonStyle()).disabled(model.activeID != nil)
      }
    case .downloading, .verifying:
      Button("Pause download") { model.pauseDownload() }.buttonStyle(SoftButtonStyle())
    case .cancelling:
      ProgressView().controlSize(.small)
    default:
      Button(
        model.state(for: manifest.modelID) == .paused
          ? String(localized: "Resume download") : String(localized: "Download")
      ) { model.download(manifest) }
      .buttonStyle(SoftButtonStyle()).disabled(model.activeID != nil || !model.supports(manifest))
    }
  }
}
