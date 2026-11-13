import Foundation
import SilliesCore

struct ZoomCallSpeakerProvider: CallSpeakerProviding {
  private(set) var evidence = CallSpeakerEvidence()

  mutating func inspect(_ node: CallSpeakerNode) -> CallSpeakerTraversal {
    let label = node.description ?? node.title ?? ""
    if node.role == "AXOutline", CallMetadataFields.words(label) == ["participants", "list"] {
      if let roster = node.readRoster() {
        zoomRoster(rows: roster.rows, declaredCount: roster.declaredCount)
      }
      return .skip
    }
    guard node.role == "AXTabGroup" else { return .children }
    return zoomTile(label) ? .skip : .children
  }

  @discardableResult mutating func zoomTile(_ description: String) -> Bool {
    guard let tile = ZoomParticipantMetadata(description) else { return false }
    observe(tile.participant)
    switch tile.activity {
    case .silent: break
    case .speaking:
      if tile.participant.identity == .remote { evidence.addSpeaker(tile.participant.name) }
    case .conflicting: evidence.invalidate()
    }
    return true
  }

  mutating func zoomRoster(rows: [String], declaredCount: Int) {
    guard declaredCount > 0, declaredCount <= CallSpeakerObservation.maximumParticipants,
      rows.count == declaredCount
    else { return }
    let participants = rows.compactMap(CallParticipantLabel.init)
    guard participants.count == declaredCount,
      Set(participants.map { $0.name.comparisonKey }).count == declaredCount
    else { return }
    for participant in participants { observe(participant) }
    evidence.declareCompleteRoster()
  }
  private mutating func observe(_ participant: CallParticipantLabel) {
    evidence.addParticipant(participant.name)
    if participant.identity == .local { evidence.setLocal(participant.name) }
  }
}
