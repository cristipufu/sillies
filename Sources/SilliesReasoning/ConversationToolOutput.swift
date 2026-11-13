import Foundation
import SilliesCore

package struct ConversationToolOutput: Sendable {
  package let briefText: String
  package let text: String
  package let sources: [ChatSource]
  package let alternatives: [String]
  package struct Evidence: Sendable {
    package let text: String
    package let sources: [ChatSource]
    package init(text: String, sources: [ChatSource]) {
      self.text = text
      self.sources = sources
    }
  }
  private var evidence: [Evidence] = []
  package func withEvidence(_ evidence: [Evidence]) -> Self {
    var copy = self
    copy.evidence = evidence
    return copy
  }
  func sources(for representation: String) -> [ChatSource] {
    guard representations.contains(representation) else { return [] }
    return evidence.first { $0.text == representation }?.sources ?? sources
  }
  var representations: [String] {
    var seen: Set<String> = []
    return ([text] + alternatives + [briefText]).filter { seen.insert($0).inserted }
  }
  package private(set) var memoryReceipt: MemoryReceipt?
  package private(set) var clarification: ChatClarification?
  package func asking(_ question: ChatClarification) -> Self {
    var copy = self
    copy.clarification = question
    return copy
  }
  package func remembering(_ receipt: MemoryReceipt) -> Self {
    var copy = self
    copy.memoryReceipt = receipt
    return copy
  }
  package init(
    text: String, sources: [ChatSource] = [], briefText: String? = nil, alternatives: [String] = []
  ) {
    self.briefText = briefText ?? text
    self.text = text
    self.sources = sources
    self.alternatives = alternatives
  }
}
