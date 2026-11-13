import Foundation

/// Timestamped UI evidence. Only an explicitly complete roster permits the two-person fallback.
public struct CallSpeakerObservation: Sendable, Equatable {
  public enum Availability: Equatable, Sendable {
    case available, unavailable, permissionDenied, unsupported
  }
  public enum Roster: Equatable, Sendable { case partial, complete }
  public struct Source: Equatable, Sendable {
    public let processID: Int32
    public let windowID: UInt32
    public init(processID: Int32, windowID: UInt32) {
      self.processID = processID
      self.windowID = windowID
    }
  }
  public let source: Source
  public static let maximumParticipants = 256
  public let capturedAt: TimeInterval
  public let availability: Availability
  public let speaking: [CallSpeakerName]
  public let participants: [CallSpeakerName]
  public let localParticipant: CallSpeakerName?
  public let roster: Roster
  public init(
    source: Source, capturedAt: TimeInterval, availability: Availability,
    speaking: [CallSpeakerName] = [],
    participants: [CallSpeakerName] = [], localParticipant: CallSpeakerName? = nil,
    roster: Roster = .partial
  ) {
    self.source = source
    self.capturedAt = capturedAt
    self.availability = availability
    self.speaking = speaking
    self.participants = participants
    self.localParticipant = localParticipant
    self.roster = roster
  }
}
