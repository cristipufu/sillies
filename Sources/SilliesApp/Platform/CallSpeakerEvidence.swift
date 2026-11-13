import SilliesCore

/// Shared evidence ownership; adapters cannot silently replace conflicting local identities.
struct CallSpeakerEvidence: Sendable {
  private(set) var speaking: [CallSpeakerName] = []
  private(set) var participants: [CallSpeakerName] = []
  private(set) var localParticipant: CallSpeakerName?
  private(set) var isAmbiguous = false
  private(set) var roster = CallSpeakerObservation.Roster.partial
  mutating func invalidate() { isAmbiguous = true }
  mutating func declareCompleteRoster() { roster = .complete }
  mutating func setLocal(_ name: CallSpeakerName) {
    if let localParticipant, localParticipant.comparisonKey != name.comparisonKey { invalidate() }
    localParticipant = name
  }
  mutating func addSpeaker(_ name: CallSpeakerName) {
    guard speaking.count < CallSpeakerObservation.maximumParticipants else {
      invalidate()
      return
    }
    if !speaking.contains(where: { $0.comparisonKey == name.comparisonKey }) {
      speaking.append(name)
    }
  }
  mutating func addParticipant(_ name: CallSpeakerName) {
    guard participants.count < CallSpeakerObservation.maximumParticipants else {
      invalidate()
      return
    }
    if !participants.contains(where: { $0.comparisonKey == name.comparisonKey }) {
      participants.append(name)
    }
  }
}
