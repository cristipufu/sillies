import Foundation

struct WritingFixtureMessage: Codable, Sendable {
  var text: String?
  var caret: Int?
}
