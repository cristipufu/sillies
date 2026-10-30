import Foundation

/// Anonymous identities are scoped to one audio source in one session.
public enum TranscriptSpeaker: Equatable, Codable, Sendable {
  case identified(Int)
  case overlapping([Int])
  case unknown

  public var label: String {
    switch self {
    case .identified(let number): "Speaker \(number)"
    case .overlapping(let numbers):
      "Speakers \(numbers.map(String.init).joined(separator: " + ")) · overlap"
    case .unknown: "Speaker unclear"
    }
  }
}
