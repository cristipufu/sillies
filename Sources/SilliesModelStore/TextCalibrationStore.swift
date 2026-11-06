import Foundation
import SilliesFileSystem

/// Optional, machine-specific overrides. Invalid or stale receipts never replace catalog defaults.
package actor TextCalibrationStore {
  private static let maximumReceiptBytes = 64 * 1024
  private let directory: URL
  private let helper: URL
  private var identities: [String: TextCalibrationIdentity] = [:]
  private var helperFingerprint: FileFingerprint?

  package init(directory: URL, helper: URL) {
    self.directory = directory
    self.helper = helper
  }

  package func resolve(_ baseline: TextModelManifest) throws -> TextModelManifest {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard let receipt = try read(baseline.modelID), receipt.isQualified,
      receipt.identity == (try identity(for: baseline))
    else { return baseline }
    return try baseline.processingPrefill(inChunksOf: receipt.chunkTokens)
  }

  package func install(_ receipt: TextCalibrationReceipt, for baseline: TextModelManifest) throws {
    guard receipt.isQualified, receipt.identity == (try identity(for: baseline)) else {
      throw ModelStoreError.invalidManifest
    }
    let location = try location(baseline.modelID)
    try ModelFiles.createDirectory(directory)
    try ModelFiles.write(receipt, to: location)
  }

  private func identity(for baseline: TextModelManifest) throws -> TextCalibrationIdentity {
    let fingerprint = try RegularFileReader.withFile(at: helper) { try $0.fingerprint() }
    if helperFingerprint != fingerprint {
      identities.removeAll()
      helperFingerprint = fingerprint
    }
    if let cached = identities[baseline.modelID], cached.revision == baseline.revision,
      cached.profile == baseline.model.profile
    {
      return cached
    }
    let identity = try TextCalibrationIdentity.capture(baseline, helper: helper)
    identities[baseline.modelID] = identity
    return identity
  }

  private func location(_ modelID: String) throws -> URL {
    try ModelFiles.child(modelID + ".json", in: directory)
  }

  private func read(_ modelID: String) throws -> TextCalibrationReceipt? {
    let location = try location(modelID)
    do {
      return try Self.readReceipt(at: location)
    } catch let error as POSIXError where error.code == .ENOENT { return nil }
  }

  package static func readReceipt(at location: URL) throws -> TextCalibrationReceipt {
    try RegularFileReader.withFile(at: location) { reader in
      guard try reader.fingerprint().size <= Self.maximumReceiptBytes else {
        throw ModelStoreError.invalidManifest
      }
      let data = try reader.readChunk() ?? Data()
      guard data.count <= Self.maximumReceiptBytes else { throw ModelStoreError.invalidManifest }
      return try JSONDecoder().decode(TextCalibrationReceipt.self, from: data)
    }
  }
}
