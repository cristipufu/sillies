import Foundation

/// Admission evidence from a paired, reviewed synthetic comparison. Latency alone cannot qualify it.
package struct TextCalibrationReceipt: Codable, Sendable {
  package struct Evidence: Codable, Sendable {
    package let baselineHash: String
    package let candidateHash: String
    package let corpusHash: String
    package let comparedCases: Int
    package let repeats: Int
    package let reviewedTurns: Int
    package let totalTurns: Int
    package let newFailures: Int
    package let baselineFirstTextMedian: Double
    package let candidateFirstTextMedian: Double
  }
  package let version: Int
  package let identity: TextCalibrationIdentity
  package let chunkTokens: Int
  package let evidence: Evidence
  private static let minimumCases = 6
  private static let minimumRepeats = 2
  private static let requiredSpeedup = 0.9

  package var isQualified: Bool {
    let proof = evidence
    let (minimumTurns, overflow) = proof.comparedCases.multipliedReportingOverflow(
      by: proof.repeats)
    return version == 1 && identity.profile.isValid
      && identity.profile.processingPrefill(inChunksOf: chunkTokens) != nil
      && proof.comparedCases >= Self.minimumCases && proof.repeats >= Self.minimumRepeats
      && !overflow && proof.totalTurns >= minimumTurns && proof.reviewedTurns == proof.totalTurns
      && proof.newFailures == 0
      && proof.baselineFirstTextMedian.isFinite && proof.baselineFirstTextMedian > 0
      && proof.candidateFirstTextMedian.isFinite && proof.candidateFirstTextMedian > 0
      && proof.candidateFirstTextMedian <= proof.baselineFirstTextMedian * Self.requiredSpeedup
      && [identity.helperSHA256, proof.baselineHash, proof.candidateHash, proof.corpusHash]
        .allSatisfy(Self.isDigest)
  }

  private static func isDigest(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}
