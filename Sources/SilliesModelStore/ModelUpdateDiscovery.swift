import CryptoKit
import Foundation

package protocol ModelUpdateDiscovering: Sendable {
  func candidate(for installed: SpeechModelManifest) async throws -> SpeechModelManifest?
}

/// Compares artifacts, not repository timestamps, so documentation edits never prompt an update.
package struct ModelUpdateDiscovery: ModelUpdateDiscovering {
  private static let metadataLimit = 4 * 1_048_576
  private static let smallFileLimit = 8 * 1_048_576
  private static let maximumArtifacts = 512
  private let client: any ModelMetadataFetching

  package init(client: any ModelMetadataFetching = ModelMetadataClient()) { self.client = client }

  private struct Repository: Decodable {
    struct File: Decodable {
      struct LargeFile: Decodable { let sha256: String }
      let rfilename: String
      let size: Int64
      let lfs: LargeFile?
    }
    let sha: String
    let siblings: [File]
  }

  package func candidate(for installed: SpeechModelManifest) async throws -> SpeechModelManifest? {
    try installed.validate()
    let references = try installed.artifacts.map { try HubModelReference($0.url) }
    var repositories: [String: Repository] = [:]
    for name in Set(references.map(\.repository)).sorted() {
      guard let url = URL(string: "https://huggingface.co/api/models/\(name)?blobs=true") else {
        throw ModelStoreError.invalidManifest
      }
      let data = try await client.fetch(url, maximumBytes: Self.metadataLimit)
      let repository = try JSONDecoder().decode(Repository.self, from: data)
      guard HubModelReference.isRevision(repository.sha) else {
        throw ModelUpdateError.layoutChanged
      }
      repositories[name] = repository
    }
    var artifacts: [ModelArtifact] = []
    for (artifact, reference) in zip(installed.artifacts, references) {
      guard let repository = repositories[reference.repository],
        let file = repository.siblings.first(where: { $0.rfilename == reference.path })
      else { throw ModelUpdateError.layoutChanged }
      if repository.sha == reference.revision {
        artifacts.append(artifact)
      } else {
        artifacts.append(
          try await updated(
            file, localPath: artifact.path, reference: reference, revision: repository.sha))
      }
    }
    // Compiled bundles are indivisible: include new support files inside an existing bundle.
    try await appendBundleAdditions(
      to: &artifacts, references: references, repositories: repositories)
    guard fingerprint(artifacts) != fingerprint(installed.artifacts) else { return nil }
    let candidate = SpeechModelManifest(
      model: installed.model.revised(to: "upstream-" + fingerprint(artifacts)), artifacts: artifacts
    )
    try candidate.validate()
    return candidate
  }

  private func appendBundleAdditions(
    to artifacts: inout [ModelArtifact], references: [HubModelReference],
    repositories: [String: Repository]
  ) async throws {
    let originals = artifacts
    for (original, reference) in zip(originals, references) {
      guard let range = reference.path.range(of: ".mlmodelc/"),
        let localRange = original.path.range(of: ".mlmodelc/"),
        let repository = repositories[reference.repository]
      else { continue }
      let remotePrefix = String(reference.path[..<range.upperBound])
      let localPrefix = String(original.path[..<localRange.upperBound])
      for file in repository.siblings where file.rfilename.hasPrefix(remotePrefix) {
        let local = localPrefix + file.rfilename.dropFirst(remotePrefix.count)
        guard !artifacts.contains(where: { $0.path == local }) else { continue }
        guard artifacts.count < Self.maximumArtifacts, ModelFiles.isSafeRelativePath(local) else {
          throw ModelUpdateError.layoutChanged
        }
        artifacts.append(
          try await updated(file, localPath: local, reference: reference, revision: repository.sha))
      }
    }
  }

  private func updated(
    _ file: Repository.File, localPath: String, reference: HubModelReference, revision: String
  ) async throws -> ModelArtifact {
    guard file.size > 0, ModelFiles.isSafeRelativePath(file.rfilename) else {
      throw ModelUpdateError.layoutChanged
    }
    let url = try reference.url(at: revision, path: file.rfilename)
    let hash: String
    if let lfs = file.lfs {
      hash = lfs.sha256
    } else {
      guard file.size <= Self.smallFileLimit else { throw ModelUpdateError.metadataTooLarge }
      let data = try await client.fetch(url, maximumBytes: Self.smallFileLimit)
      guard data.count == file.size else { throw ModelUpdateError.layoutChanged }
      hash = digest(data)
    }
    return ModelArtifact(path: localPath, url: url, byteCount: file.size, sha256: hash)
  }

  private func fingerprint(_ artifacts: [ModelArtifact]) -> String {
    let content = artifacts.filter { !$0.path.lowercased().hasSuffix(".md") }
      .sorted { $0.path < $1.path }.map { "\($0.path):\($0.byteCount):\($0.sha256)" }.joined(
        separator: "\n")
    return digest(Data(content.utf8))
  }

  private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
