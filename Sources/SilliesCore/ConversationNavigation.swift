import Foundation

/// Navigation is useful only when it can reveal messages outside the current view.
public struct ConversationNavigation: Equatable, Sendable {
  public let showsEarlier: Bool
  public let showsLatest: Bool

  public init(
    latestMessageID: UUID?, hasEarlierMessages: Bool, page: ConversationPage?, nearBottom: Bool
  ) {
    showsEarlier = page == nil && hasEarlierMessages && latestMessageID != nil
    let hasMessages = latestMessageID != nil || page?.entries.isEmpty == false
    let pageMissesLatest =
      page.map {
        $0.hasNewer || (latestMessageID != nil && $0.entries.last?.id != latestMessageID)
      } ?? false
    showsLatest = hasMessages && (pageMissesLatest || !nearBottom)
  }
}
