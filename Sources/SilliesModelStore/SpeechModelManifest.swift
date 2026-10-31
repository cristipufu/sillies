import Foundation
import SilliesCore

package struct SpeechModelManifest: Codable, Equatable, ModelArtifactManifest {
  package let model: SpeechModelDescriptor
  package let artifacts: [ModelArtifact]
  package var modelID: String { model.id }
  package var revision: String { model.revision }
  package init(model: SpeechModelDescriptor, artifacts: [ModelArtifact]) {
    self.model = model
    self.artifacts = artifacts
  }

  package func validate() throws {
    try validateArtifacts()
  }

}
