import Foundation
import SilliesCore

package struct SpeechModelManifest: Codable, Equatable, Sendable {
  private static let maximumArtifacts = 512
  private static let maximumArtifactBytes: Int64 = 8 * 1_024 * 1_024 * 1_024
  private static let maximumDownloadBytes: Int64 = 16 * 1_024 * 1_024 * 1_024
  package let model: SpeechModelDescriptor
  package let artifacts: [ModelArtifact]
  package var downloadBytes: Int64 { artifacts.reduce(0) { $0 + $1.byteCount } }
  package init(model: SpeechModelDescriptor, artifacts: [ModelArtifact]) {
    self.model = model
    self.artifacts = artifacts
  }

  package func validate() throws {
    guard ModelFiles.isSafeComponent(model.id), ModelFiles.isSafeComponent(model.revision),
      !artifacts.isEmpty, artifacts.count <= Self.maximumArtifacts,
      Set(artifacts.map(\.path)).count == artifacts.count
    else { throw ModelStoreError.invalidManifest }
    for artifact in artifacts {
      guard ModelFiles.isSafeRelativePath(artifact.path), artifact.byteCount > 0,
        artifact.byteCount <= Self.maximumArtifactBytes,
        artifact.sha256.count == 64, artifact.sha256.allSatisfy(\.isHexDigit)
      else { throw ModelStoreError.invalidManifest }
      _ = try HubModelReference(artifact.url)
    }
    guard downloadBytes <= Self.maximumDownloadBytes else { throw ModelStoreError.invalidManifest }
  }

}
