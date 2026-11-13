import Foundation
import SilliesCore

struct MeetCallSpeakerProvider: CallSpeakerProviding {
  private static let speakingIndicator = "v5h6Xc"
  private static let maximumAncestorDistance = 7
  private static let maximumClasses = 64
  private static let maximumClassBytes = 128
  private(set) var evidence = CallSpeakerEvidence()

  mutating func inspect(_ node: CallSpeakerNode) -> CallSpeakerTraversal {
    if node.role == "AXWebArea" {
      guard let url = node.url,
        url.absoluteString.utf8.count <= CallSpeakerText.maximumMetadataBytes,
        url.scheme == "https", url.host?.lowercased() == "meet.google.com"
      else { return .skip }
      return .callPage
    }
    guard node.scope == .verifiedCallPage, node.role == "AXGroup" else { return .children }
    guard node.classes.count <= Self.maximumClasses,
      node.classes.allSatisfy({ $0.utf8.count <= Self.maximumClassBytes })
    else {
      evidence.invalidate()
      return .skip
    }
    guard node.classes.contains(Self.speakingIndicator) else { return .children }
    guard let texts = node.readSpeakingTile(Self.maximumAncestorDistance) else {
      evidence.invalidate()
      return .skip
    }
    meetSpeakingTile(texts: texts)
    return .skip
  }

  mutating func meetSpeakingTile(texts: [String]) {
    guard let tile = MeetParticipantMetadata(texts: texts) else {
      evidence.invalidate()
      return
    }
    let person = tile.participant
    if person.identity == .local || person.name.comparisonKey == "you" {
      evidence.setLocal(person.name)
    } else {
      evidence.addSpeaker(person.name)
    }
    evidence.addParticipant(person.name)
  }
}
