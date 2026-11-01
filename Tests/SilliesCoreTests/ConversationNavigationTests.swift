import Foundation
import Testing

@testable import SilliesCore

@Test func emptyAndFullyVisibleChatsHaveNoNavigationControls() {
  let empty = ConversationNavigation(
    latestMessageID: nil, hasEarlierMessages: false, page: nil, nearBottom: false)
  #expect(!empty.showsEarlier && !empty.showsLatest)
  let latest = UUID()
  let visible = ConversationNavigation(
    latestMessageID: latest, hasEarlierMessages: false, page: nil, nearBottom: true)
  #expect(!visible.showsEarlier && !visible.showsLatest)
  let reading = ConversationNavigation(
    latestMessageID: latest, hasEarlierMessages: false, page: nil, nearBottom: false)
  #expect(!reading.showsEarlier && reading.showsLatest)
}

@Test func historyNavigationDistinguishesLoadedMessagesFromUnloadedPages() {
  let newest = ChatMessage(role: .user, text: "Today")
  let entry = ConversationEntry(sequence: 200, message: newest, createdAt: .distantPast)
  let recent = ConversationNavigation(
    latestMessageID: newest.id, hasEarlierMessages: true, page: nil, nearBottom: true)
  #expect(recent.showsEarlier && !recent.showsLatest)
  let latestPage = ConversationPage(entries: [entry], hasOlder: true, hasNewer: false)
  let browsingLatest = ConversationNavigation(
    latestMessageID: newest.id, hasEarlierMessages: true, page: latestPage, nearBottom: true)
  #expect(!browsingLatest.showsEarlier && !browsingLatest.showsLatest)
  let readingPage = ConversationNavigation(
    latestMessageID: newest.id, hasEarlierMessages: true, page: latestPage, nearBottom: false)
  #expect(readingPage.showsLatest)
  let arrivedDuringBrowsing = ConversationNavigation(
    latestMessageID: UUID(), hasEarlierMessages: true, page: latestPage, nearBottom: true)
  #expect(arrivedDuringBrowsing.showsLatest)
  let olderPage = ConversationPage(entries: [entry], hasOlder: false, hasNewer: true)
  let browsingOlder = ConversationNavigation(
    latestMessageID: newest.id, hasEarlierMessages: true, page: olderPage, nearBottom: true)
  #expect(!browsingOlder.showsEarlier && browsingOlder.showsLatest)
}
