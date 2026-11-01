import Foundation
import SilliesFileSystem

/// Owned by ModelStore's actor. Evidence is bounded, process-local, and never trusted from disk.
final class ModelArtifactVerifier {
  private struct Verification: Hashable {
    let fingerprint: FileFingerprint
    let digest: String
  }
  private static let maximumCachedFiles = 4_096
  private var verified: Set<Verification> = []
  private let digest: (RegularFileReader) throws -> String

  init(digest: @escaping (RegularFileReader) throws -> String = ModelFileDigest.sha256) {
    self.digest = digest
  }

  func verify(_ artifact: ModelArtifact, at url: URL) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    try RegularFileReader.withFile(at: url) { file in
      try validateContents(artifact, file: file, location: url)
    }
  }

  private func validateContents(_ artifact: ModelArtifact, file: RegularFileReader, location: URL)
    throws
  {
    let fingerprint = try file.fingerprint()
    guard fingerprint.size == artifact.byteCount else {
      throw ModelStoreError.invalidArtifact(artifact.path)
    }
    let evidence = Verification(fingerprint: fingerprint, digest: artifact.sha256)
    guard !verified.contains(evidence) else { return }
    guard try digest(file) == artifact.sha256,
      try file.fingerprint() == fingerprint,
      try RegularFileReader.withFile(at: location, { try $0.fingerprint() }) == fingerprint
    else { throw ModelStoreError.invalidArtifact(artifact.path) }
    try Task.checkCancellation()
    guard fingerprint.supportsReuse else { return }
    if verified.count == Self.maximumCachedFiles { verified.removeAll(keepingCapacity: true) }
    verified.insert(evidence)
  }

}
