import Foundation
import SilliesCore
import Synchronization
import Testing

@testable import SilliesVault

@Test func conversationDateNavigationIncludesTheSelectedDayAndStaysBounded() async throws {
  let fixture = NavigationExportFixture()
  defer { fixture.remove() }
  let store = fixture.store
  let opened = try await store.open(.init(id: "pogo", name: "Pogo"))
  for day in 0..<3 {
    try await store.save(
      .init(
        handle: opened.handle,
        messages: (0..<90).map { .init(role: .user, text: "day \(day) message \($0)") },
        checkpoint: .init(), savedAt: fixture.date.addingTimeInterval(Double(day) * 86_400)))
  }
  let page = try await store.page(
    .init(handle: opened.handle, position: .onOrAfter(fixture.date.addingTimeInterval(86_400))))
  #expect(page.entries.count == ConversationPageRequest.defaultLimit)
  #expect(page.entries.first?.message.text == "day 1 message 0")
  #expect(page.hasOlder && page.hasNewer)
  let empty = try await store.page(
    .init(handle: opened.handle, position: .onOrAfter(fixture.date.addingTimeInterval(4 * 86_400))))
  #expect(empty.entries.isEmpty)
  await #expect(throws: ConversationStorageError.self) {
    try await store.page(
      .init(handle: opened.handle, position: .onOrAfter(Date(timeIntervalSince1970: .nan))))
  }
}

@Test func conversationExportStreamsTheArchiveAndExcludesDraftsAndLaterMessages() async throws {
  let fixture = NavigationExportFixture()
  defer { fixture.remove() }
  let store = fixture.store
  let opened = try await store.open(.init(id: "pogo", name: "Pogo"))
  let messages = (0..<2_000).map {
    ChatMessage(role: $0.isMultiple(of: 2) ? .user : .companion, text: "Message \($0) · café")
  }
  try await store.save(
    .init(
      handle: opened.handle, messages: messages, checkpoint: .init(draft: "Private unsent draft"),
      savedAt: fixture.date))
  let progress = Mutex<[Int]>([])
  let lateWrite = Mutex(false)
  let count = try await store.exportConversation(
    .init(handle: opened.handle, companionName: "Pogo"), to: fixture.destination
  ) { count in
    progress.withLock { $0.append(count) }
    let shouldWrite = lateWrite.withLock { written in
      if written { return false }
      written = true
      return true
    }
    if shouldWrite {
      do {
        try await store.save(
          .init(
            handle: opened.handle, messages: [.init(role: .user, text: "Arrived during export")],
            checkpoint: .init(), savedAt: fixture.date))
      } catch { Issue.record(error) }
    }
  }
  #expect(count == messages.count)
  #expect(progress.withLock { $0.count } > 1)
  let text = try String(contentsOf: fixture.destination, encoding: .utf8)
  #expect(text.contains("Message 0 · café") && text.contains("Message 1999 · café"))
  #expect(!text.contains("Private unsent draft") && !text.contains("Arrived during export"))
  #expect(text.components(separatedBy: "## ").count - 1 == messages.count)
  #expect(
    try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).filter {
      $0.hasSuffix(".tmp")
    }.isEmpty)
}

@Test func cancelledConversationExportPreservesAnExistingFileAndCleansItsTemporary() async throws {
  let fixture = NavigationExportFixture()
  defer { fixture.remove() }
  let opened = try await fixture.store.open(.init(id: "pogo", name: "Pogo"))
  try await fixture.store.save(
    .init(
      handle: opened.handle, messages: (0..<180).map { .init(role: .user, text: "\($0)") },
      checkpoint: .init(), savedAt: fixture.date))
  try Data("Existing export".utf8).write(to: fixture.destination)
  let task = Task {
    try await fixture.store.exportConversation(
      .init(handle: opened.handle, companionName: "Pogo"), to: fixture.destination
    ) { _ in
      withUnsafeCurrentTask { $0?.cancel() }
    }
  }
  await #expect(throws: CancellationError.self) { try await task.value }
  #expect(try String(contentsOf: fixture.destination, encoding: .utf8) == "Existing export")
  #expect(
    try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).filter {
      $0.hasSuffix(".tmp")
    }.isEmpty)
}

@Test func clearingHistoryDuringExportCannotPublishADeletedConversation() async throws {
  let fixture = NavigationExportFixture()
  defer { fixture.remove() }
  let opened = try await fixture.store.open(.init(id: "pogo", name: "Pogo"))
  try await fixture.store.save(
    .init(
      handle: opened.handle, messages: [.init(role: .user, text: "Forgotten")], checkpoint: .init(),
      savedAt: fixture.date))
  await #expect(throws: ConversationStorageError.self) {
    try await fixture.store.exportConversation(
      .init(handle: opened.handle, companionName: "Pogo"), to: fixture.destination
    ) { _ in
      do { _ = try await fixture.store.clear(opened.handle) } catch { Issue.record(error) }
    }
  }
  #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
}

@Test func conversationExportCannotReplaceItsArchiveOrAnExistingDirectory() async throws {
  let fixture = NavigationExportFixture()
  defer { fixture.remove() }
  let opened = try await fixture.store.open(.init(id: "pogo", name: "Pogo"))
  for destination in [
    fixture.directory.appendingPathComponent("conversations.sqlite"), fixture.directory,
  ] {
    await #expect(throws: CocoaError.self) {
      try await fixture.store.exportConversation(
        .init(handle: opened.handle, companionName: "Pogo"), to: destination, progress: { _ in })
    }
  }
  #expect(try await fixture.store.open(.init(id: "pogo", name: "Pogo")).handle == opened.handle)
}

private struct NavigationExportFixture: Sendable {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let date = Date(timeIntervalSince1970: 1_780_000_000)
  var destination: URL { directory.appendingPathComponent("conversation.md") }
  let store: ConversationLibrary
  init() { store = ConversationLibrary(directory: directory) }
  func remove() {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }
}
