import Foundation

public struct ConversationExportRequest: Sendable {
  public let handle: ConversationHandle
  public let companionName: String
  public init(handle: ConversationHandle, companionName: String) {
    self.handle = handle
    self.companionName = companionName
  }
}

/// Optional archive capability. Export reads bounded pages and never replaces a UI page.
public protocol ConversationExporting: Sendable {
  func exportConversation(
    _ request: ConversationExportRequest, to destination: URL,
    progress: @escaping @Sendable (Int) async -> Void
  ) async throws -> Int
}
