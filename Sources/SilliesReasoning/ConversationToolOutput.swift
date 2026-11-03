import Foundation
import SilliesCore

package struct ConversationToolOutput: Sendable {
  package let briefText: String
  package let text: String
  package let sources: [ChatSource]
  package let alternatives: [String]
  var representations: [String] {
    var seen: Set<String> = []
    return ([text] + alternatives + [briefText]).filter { seen.insert($0).inserted }
  }
  package private(set) var memoryReceipt: MemoryReceipt?
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
