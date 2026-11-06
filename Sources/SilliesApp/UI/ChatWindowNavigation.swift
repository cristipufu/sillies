import Observation

/// Conversation utilities share the mascot's bubble instead of dimming a transparent sheet parent.
@MainActor @Observable final class ChatWindowNavigation {
  enum Page { case conversation, memories, search, vault }
  private(set) var page = Page.conversation

  func show(_ page: Page) { self.page = page }
}
