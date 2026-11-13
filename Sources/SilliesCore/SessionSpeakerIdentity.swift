import Foundation

public struct SessionSpeakerIdentity: Identifiable, Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case voice(Int)
    case participant(CallSpeakerName)
  }
  public let source: String
  public let kind: Kind
  public let suggestedName: CallSpeakerName?
  public init(source: String, number: Int, suggestedName: CallSpeakerName? = nil) {
    self.source = source
    kind = .voice(number)
    self.suggestedName = suggestedName
  }
  public init(source: String, participant: CallSpeakerName) {
    self.source = source
    kind = .participant(participant)
    suggestedName = participant
  }
  public var id: String {
    switch kind {
    case .voice(let number): "\(source):\(number)"
    case .participant(let name): "\(source):participant:\(name.comparisonKey)"
    }
  }
  public var label: String {
    switch kind {
    case .voice(let number): String(localized: "\(source) · Speaker \(number)")
    case .participant(let name): String(localized: "\(source) · \(name.rawValue)")
    }
  }
}
