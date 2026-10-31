import Foundation

package struct SpeechRecognitionContext: Sendable {
  package enum Priority: Int, Sendable { case live, interactive }
  package var vocabulary: [String]
  package var priority: Priority
  package init(vocabulary: [String] = [], priority: Priority = .live) {
    self.vocabulary = vocabulary
    self.priority = priority
  }
}
