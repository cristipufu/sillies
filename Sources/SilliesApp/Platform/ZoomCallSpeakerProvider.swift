import Foundation
import SilliesCore

struct ZoomCallSpeakerProvider: CallSpeakerProviding {
  private(set) var evidence = CallSpeakerEvidence()
  var visualInterpreter: (any CallSpeakerVisualInterpreting)? { ZoomSpeakerHighlight() }

  mutating func inspect(_ node: CallSpeakerNode) -> CallSpeakerTraversal {
    let label = node.description ?? node.title ?? ""
    if node.role == "AXOutline", CallMetadataFields.words(label) == ["participants", "list"] {
      if let roster = node.readRoster() {
        zoomRoster(rows: roster.rows, declaredCount: roster.declaredCount)
      }
      return .skip
    }
    guard node.role == "AXTabGroup" else { return .children }
    guard let tile = ZoomParticipantMetadata(label) else { return .children }
    observe(tile)
    if let frame = node.readFrame() {
      evidence.addVisualTile(
        .init(
          name: tile.participant.name, frame: frame,
          audio: tile.audio == .muted ? .muted : .unmuted))
    }
    return .skip
  }

  @discardableResult mutating func zoomTile(_ description: String) -> Bool {
    guard let tile = ZoomParticipantMetadata(description) else { return false }
    observe(tile)
    return true
  }

  private mutating func observe(_ tile: ZoomParticipantMetadata) {
    observe(tile.participant)
    switch tile.activity {
    case .silent: break
    case .speaking:
      if tile.participant.identity == .remote { evidence.addSpeaker(tile.participant.name) }
    case .conflicting: evidence.invalidate()
    }
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
