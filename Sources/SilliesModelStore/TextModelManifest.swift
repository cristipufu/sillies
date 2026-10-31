import Foundation
import SilliesCore

package struct TextModelManifest: Codable, Equatable, ModelArtifactManifest {
  package let model: TextModelDescriptor
  package let artifacts: [ModelArtifact]
  package var modelID: String { model.id }
  package var revision: String { model.revision }

  package func validate() throws {
    try validateArtifacts()
    guard !model.providerID.isEmpty, model.minimumMemoryGB > 0,
      (2_048...8_192).contains(model.contextTokens), model.sourceURL.scheme == "https"
    else { throw ModelStoreError.invalidManifest }
    for artifact in artifacts {
      let reference = try HubModelReference(artifact.url)
      guard reference.revision == revision, reference.path == artifact.path else {
        throw ModelStoreError.invalidManifest
      }
    }
  }
}
