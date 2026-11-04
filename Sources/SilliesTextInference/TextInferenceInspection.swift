import CryptoKit
import Foundation
import SilliesTextModels

/// Explicit, synthetic diagnostics share dispatch without expanding the production IPC loop.
enum TextInferenceInspection {
  struct Reproduction: Sendable {
    var samplingSeed: UInt64?
    var prefixRetention = MLXPrefixSnapshot.Retention.retained
  }
  static func reproduction(_ arguments: [String]) throws -> Reproduction {
    let flag = "--diagnostic-prefix-retention"
    let positions = arguments.indices.filter { arguments[$0] == flag }
    let seed = try samplingSeed(arguments)
    guard let position = positions.first else { return .init(samplingSeed: seed) }
    guard positions.count == 1, position + 1 < arguments.count,
      let retention = MLXPrefixSnapshot.Retention(rawValue: arguments[position + 1])
    else { throw TextModelError.invalidResponse }
    return .init(samplingSeed: seed, prefixRetention: retention)
  }
  /// Only seeded synthetic diagnostics opt into this content-free record.
  static func recordFingerprint(_ tokens: [Int]) {
    let bytes = tokens.map { Int64($0).littleEndian }.withUnsafeBytes { Data($0) }
    let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    fputs("TOKEN_FINGERPRINT count=\(tokens.count) sha256=\(digest)\n", stderr)
  }
  /// Opt-in reproducibility for synthetic probes. The app never supplies this diagnostic flag.
  static func samplingSeed(_ arguments: [String]) throws -> UInt64? {
    let flag = "--diagnostic-sampling-seed"
    let positions = arguments.indices.filter { arguments[$0] == flag }
    guard let position = positions.first else { return nil }
    guard positions.count == 1, position + 1 < arguments.count,
      let seed = UInt64(arguments[position + 1])
    else { throw TextModelError.invalidResponse }
    return seed
  }
  private enum Kind: String {
    case prefixLifecycle = "--inspect-prefix-lifecycle"
    case prefixState = "--inspect-prefix-state"
    case prefixCapacity = "--inspect-prefix-capacity"
    case generation = "--inspect-generation"
    case tokenizer = "--inspect-tokenizer"
  }

  static func runIfRequested(_ arguments: [String]) async throws -> Bool {
    guard arguments.count == 3, let kind = Kind(rawValue: arguments[1]) else { return false }
    let requestURL = URL(fileURLWithPath: arguments[2])
    switch kind {
    case .prefixLifecycle: try await TextPrefixLifecycleInspection.run(requestURL: requestURL)
    case .prefixState: try await TextPrefixStateInspection.run(requestURL: requestURL)
    case .prefixCapacity: try await TextPrefixCapacityInspection.run(requestURL: requestURL)
    case .generation: try await TextGenerationInspection.run(requestURL: requestURL)
    case .tokenizer: try await TextTokenizerInspection.run(requestURL: requestURL)
    }
    return true
  }
}
