import Foundation
import SilliesCore

/// An injected capability. Only its implementation can access the underlying local store.
package protocol ConversationTool: Sendable {
  var definition: ConversationToolDefinition { get }
  var activity: String { get }
  func call(arguments: Data) async throws -> ConversationToolOutput
}
