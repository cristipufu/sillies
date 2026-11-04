import Synchronization
import Testing

@testable import SilliesChat

@Test func slowChatPresentationRetainsOnlyTheLatestPendingSnapshot() async {
  let (entered, entry) = AsyncStream<Void>.makeStream()
  let (released, release) = AsyncStream<Void>.makeStream()
  let delivered = Mutex<[String]>([])
  let presentation = ChatTextPresentation { text in
    delivered.withLock { $0.append(text) }
    if text == "first" {
      entry.yield(())
      for await _ in released { break }
    }
  }
  await presentation.submit("first")
  for await _ in entered { break }
  for index in 1...1_000 { await presentation.submit("snapshot \(index)") }
  #expect(delivered.withLock { $0 } == ["first"])
  release.yield(())
  await presentation.finish()
  #expect(delivered.withLock { $0 } == ["first", "snapshot 1000"])
  await presentation.submit("late update")
  #expect(delivered.withLock { $0 } == ["first", "snapshot 1000"])
}

@Test func finishingChatPresentationJoinsTheFinalDelivery() async {
  let (entered, entry) = AsyncStream<Void>.makeStream()
  let (released, release) = AsyncStream<Void>.makeStream()
  let received = Mutex(false)
  let presentation = ChatTextPresentation { _ in
    entry.yield(())
    for await _ in released { break }
    received.withLock { $0 = true }
  }
  await presentation.submit("final")
  for await _ in entered { break }
  #expect(!received.withLock { $0 })
  release.yield(())
  await presentation.finish()
  #expect(received.withLock { $0 })
  await presentation.finish()
}
