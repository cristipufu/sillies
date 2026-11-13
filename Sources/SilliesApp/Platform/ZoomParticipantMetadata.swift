import Foundation

/// A tile has one audio-control boundary; name punctuation belongs to everything before it.
struct ZoomParticipantMetadata {
  enum Activity { case silent, speaking, conflicting }
  private enum AudioState { case muted, unmuted }
  let participant: CallParticipantLabel
  let activity: Activity

  init?(_ description: String) {
    guard let fields = CallMetadataFields(description)?.values else { return nil }
    let audio = fields.indices.compactMap { index -> (Int, AudioState)? in
      Self.audioState(fields[index]).map { (index, $0) }
    }
    guard audio.count == 1, let (boundary, audioState) = audio.first, boundary > 0,
      let participant = CallParticipantLabel(fields[..<boundary].joined(separator: ", "))
    else { return nil }
    let isSpeaking = fields.dropFirst(boundary + 1).contains {
      CallMetadataFields.words($0) == ["active", "speaker"]
    }
    self.participant = participant
    if isSpeaking {
      activity = audioState == .unmuted ? .speaking : .conflicting
    } else {
      activity = .silent
    }
  }
  private static func audioState(_ value: String) -> AudioState? {
    let words = CallMetadataFields.words(value)
    guard words.count == 3, words.prefix(2) == ["computer", "audio"] else { return nil }
    switch words.last {
    case "muted": return .muted
    case "unmuted": return .unmuted
    default: return nil
    }
  }
}
