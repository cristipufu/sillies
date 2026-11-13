import Observation
import SilliesCore

/// Conversation utilities share the mascot's bubble instead of dimming a transparent sheet parent.
@MainActor @Observable final class ChatWindowNavigation {
  enum Page: Equatable {
    case conversation, memories, search, vault
    case sources([ChatSource])
  }
  private(set) var page = Page.conversation

  func show(_ page: Page) { self.page = page }
}
