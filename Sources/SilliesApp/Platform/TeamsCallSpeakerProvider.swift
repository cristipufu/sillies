import Foundation
import SilliesCore

struct TeamsCallSpeakerProvider: CallSpeakerProviding {
  private(set) var evidence = CallSpeakerEvidence()
  mutating func inspect(_ node: CallSpeakerNode) -> CallSpeakerTraversal {
    guard node.role == "AXGroup" || node.role == "AXRow" else { return .children }
    let participants = [node.description, node.title].compactMap { label in
      label.flatMap(TeamsSpeakingMetadata.participant)
    }
    guard Set(participants.map { $0.name.comparisonKey }).count <= 1 else {
      evidence.invalidate()
      return .skip
    }
    for participant in participants { observe(participant) }
    return .children
  }
  mutating func teamsSpeakingLabel(_ label: String) {
    if let participant = TeamsSpeakingMetadata.participant(in: label) { observe(participant) }
  }
  private mutating func observe(_ participant: CallParticipantLabel) {
    let standaloneSelf = ["you", "me"].contains(participant.name.comparisonKey)
    if participant.identity == .local || standaloneSelf {
      evidence.setLocal(participant.name)
    } else {
      evidence.addSpeaker(participant.name)
    }
    evidence.addParticipant(participant.name)
  }
}
