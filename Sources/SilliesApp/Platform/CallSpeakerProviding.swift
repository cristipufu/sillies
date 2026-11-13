import Foundation

/// Providers see typed metadata and request text only from a recognized call-specific container.
protocol CallSpeakerProviding: Sendable {
  var evidence: CallSpeakerEvidence { get }
  mutating func inspect(_ node: CallSpeakerNode) -> CallSpeakerTraversal
}
enum CallSpeakerTraversal { case children, callPage, skip }
struct CallSpeakerRoster {
  let rows: [String]
  let declaredCount: Int
}
struct CallSpeakerNode {
  enum Scope { case window, verifiedCallPage }
  let role: String
  var description: String?
  var title: String?
  var classes: [String] = []
  var url: URL?
  var scope = Scope.window
  var readRoster: () -> CallSpeakerRoster? = { nil }
  var readSpeakingTile: (Int) -> [String]? = { _ in nil }
}
typealias CallSpeakerProviderFactory =
  @Sendable (String) -> (any CallSpeakerProviding)?
