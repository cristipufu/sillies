import Foundation
import SilliesCore

/// Separates a participant's display name from explicit trailing meeting-role annotations.
struct CallParticipantLabel {
  enum Identity { case local, remote }
  let name: CallSpeakerName
  let identity: Identity

  init?(_ label: String) {
    guard label.utf8.count <= CallSpeakerText.maximumMetadataBytes else { return nil }
    var remaining = label.precomposedStringWithCompatibilityMapping
      .trimmingCharacters(in: .whitespacesAndNewlines)
    var identity = Identity.remote
    while remaining.last == ")", let opening = remaining.lastIndex(of: "(") {
      let content = remaining[
        remaining.index(after: opening)..<remaining.index(before: remaining.endIndex)]
      let annotations = content.split(
        omittingEmptySubsequences: false, whereSeparator: { $0 == "," || $0 == "、" }
      )
      .map { CallSpeakerText.normalize(String($0)) }
      guard !annotations.isEmpty, annotations.allSatisfy(Self.isMeetingRole) else { break }
      if annotations.contains(where: Self.isLocalRole) { identity = .local }
      remaining = String(remaining[..<opening]).trimmingCharacters(in: .whitespaces)
    }
    guard let name = CallSpeakerName(rawValue: remaining) else { return nil }
    self.name = name
    self.identity = identity
  }

  private static func isMeetingRole(_ value: String) -> Bool {
    isLocalRole(value) || ["host", "co-host", "guest", "interpreter"].contains(value)
  }
  private static func isLocalRole(_ value: String) -> Bool { value == "me" || value == "you" }
}
