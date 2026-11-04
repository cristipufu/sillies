import Foundation
import SilliesCore
import Testing

@testable import SilliesChat

@Test @MainActor func memoryBrowserDiscardsClosedCancelledAndReplacedReads() async throws {
  let repository = MemoryBrowserProbe()
  let browser = ChatMemoryBrowser(repository: repository)
  let handle = ConversationHandle(companionID: "pogo", generation: UUID())
  try await browser.refresh(handle)
  let initial = browser.page.facts
  await repository.suspendNext()
  let oldRead = Task { await browser.show(.latest) }
  await repository.waitForRead()
  browser.invalidate()
  await repository.release()
  await oldRead.value
  #expect(browser.page.facts == initial)
  #expect(!browser.isLoading)

  await repository.suspendNext()
  let cancelled = Task { await browser.show(.latest) }
  await repository.waitForRead()
  cancelled.cancel()
  await repository.release()
  await cancelled.value
  #expect(browser.page.facts == initial)
  #expect(browser.failure == nil)

  await repository.suspendNext()
  let stale = Task { await browser.show(.latest) }
  await repository.waitForRead()
  let other = ConversationHandle(companionID: "bolt", generation: UUID())
  try await browser.refresh(other)
  let current = browser.page.facts
  await repository.release()
  await stale.value
  #expect(browser.page.facts == current)
  #expect(browser.page.facts.first?.value == "bolt")
}

@Test @MainActor func memoryBrowserKeepsOnlyOnePageAndBoundsLiveReceipts() async throws {
  let repository = MemoryBrowserProbe()
  let browser = ChatMemoryBrowser(repository: repository)
  let handle = ConversationHandle(companionID: "pogo", generation: UUID())
  try await browser.refresh(handle)
  for index in 0..<100 {
    let fact = CompanionMemory(
      replacing: nil, fact: .init(key: "fact_\(index)", value: "\(index)"),
      source: .init(messageID: UUID(), quote: "Synthetic fact \(index)"), savedAt: Date())
    browser.received(.init(handle: handle, id: UUID(), previous: nil, saved: fact))
  }
  #expect(browser.page.facts.count == CompanionMemoryPageRequest.pageSize)
  let next = try #require(browser.page.next)
  await browser.show(.before(next))
  #expect(browser.page.facts.count == 1)
  #expect(browser.page.facts.first?.value == "pogo")
}

@Test @MainActor func anEmptyOlderMemoryPageReturnsToTheAvailableFacts() async throws {
  let repository = MemoryBrowserProbe()
  let browser = ChatMemoryBrowser(repository: repository)
  try await browser.refresh(.init(companionID: "pogo", generation: UUID()))
  let cursor = CompanionMemoryCursor(try #require(browser.page.facts.first))
  await repository.removeOlderFacts()
  let revision = browser.pageRevision
  await browser.show(.before(cursor))
  #expect(browser.page.facts.first?.value == "pogo")
  #expect(browser.pageRevision != revision)
  #expect(browser.failure == nil)
}

private actor MemoryBrowserProbe: CompanionMemoryRepository {
  private var shouldSuspend = false
  private var olderFactsRemoved = false
  private var suspended: CheckedContinuation<Void, Never>?
  private var observer: CheckedContinuation<Void, Never>?

  func suspendNext() { shouldSuspend = true }
  func removeOlderFacts() { olderFactsRemoved = true }
  func waitForRead() async {
    if suspended != nil { return }
    await withCheckedContinuation { observer = $0 }
  }
  func release() {
    suspended?.resume()
    suspended = nil
  }
  func memoryPage(_ request: CompanionMemoryPageRequest) async -> CompanionMemoryPage {
    if shouldSuspend {
      shouldSuspend = false
      await withCheckedContinuation {
        suspended = $0
        observer?.resume()
        observer = nil
      }
    }
    if olderFactsRemoved, case .before = request.position { return .init(facts: [], next: nil) }
    return .init(
      facts: [
        CompanionMemory(
          replacing: nil, fact: .init(key: "name", value: request.handle.companionID),
          source: .init(messageID: UUID(), quote: "Synthetic source"), savedAt: Date())
      ], next: nil)
  }
  func memories(_ query: CompanionMemoryQuery) -> [CompanionMemory] { [] }
  func remember(_ request: MemoryWrite) throws -> MemoryReceipt {
    throw ConversationStorageError.invalidData
  }
  func forget(_ handle: ConversationHandle, id: UUID) throws -> ConversationSnapshot {
    throw ConversationStorageError.invalidData
  }
  func undoMemory(_ handle: ConversationHandle, receiptID: UUID) throws -> ConversationSnapshot {
    throw ConversationStorageError.invalidData
  }
  func recentMemoryChanges(_ handle: ConversationHandle) -> [MemoryReceipt] { [] }
}
