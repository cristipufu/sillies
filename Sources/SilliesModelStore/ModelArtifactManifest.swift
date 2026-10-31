import Foundation

/// Storage depends on artifact identity, not on the task an inference model performs.
package protocol ModelArtifactManifest: Sendable {
  var modelID: String { get }
  var revision: String { get }
  var artifacts: [ModelArtifact] { get }
  func validate() throws
}

extension ModelArtifactManifest {
  package var downloadBytes: Int64 { artifacts.reduce(0) { $0 + $1.byteCount } }

  package func validateArtifacts() throws {
    guard ModelFiles.isSafeComponent(modelID), ModelFiles.isSafeComponent(revision),
      !artifacts.isEmpty, artifacts.count <= ModelArtifactLimits.maximumCount,
      Set(artifacts.map(\.path)).count == artifacts.count
    else { throw ModelStoreError.invalidManifest }
    for artifact in artifacts {
      guard ModelFiles.isSafeRelativePath(artifact.path), artifact.byteCount > 0,
        artifact.byteCount <= ModelArtifactLimits.maximumFileBytes,
        artifact.sha256.count == 64, artifact.sha256.allSatisfy(\.isHexDigit)
      else { throw ModelStoreError.invalidManifest }
      _ = try HubModelReference(artifact.url)
    }
    guard downloadBytes <= ModelArtifactLimits.maximumTotalBytes else {
      throw ModelStoreError.invalidManifest
    }
  }
}

private enum ModelArtifactLimits {
  static let maximumCount = 512
  static let maximumFileBytes: Int64 = 8 * 1_024 * 1_024 * 1_024
  static let maximumTotalBytes: Int64 = 16 * 1_024 * 1_024 * 1_024
}
