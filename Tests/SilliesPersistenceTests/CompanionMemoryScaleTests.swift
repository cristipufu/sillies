import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test(arguments: [200, 1_000, 10_000])
func memorySearchRanksRelevantOlderFactsWithBoundedPages(_ count: Int) async throws {
  let fixture = try MemoryScaleFixture(count: count)
  defer { fixture.remove() }
  let database = fixture.database
  let search = try ConversationSearchDatabase(directory: fixture.directory)
  var baselineHits = 0
  var rankedHits = 0
  var durations: [Double] = []
  for index in 0..<MemoryScaleFixture.topicCount {
    let query = "project\(index) courier"
    let expression = try #require(VaultSearchTerms.expression(query, matching: .anyTerm))
    var baseline: [CompanionMemory] = []
    try database.sql.rows(
      """
      SELECT body FROM companion_memories WHERE owner=?
      AND id IN (SELECT id FROM memory_search WHERE memory_search MATCH ?)
      ORDER BY updated DESC LIMIT 4
      """, [.text(fixture.handle.companionID), .text(expression)]
    ) { row in
      baseline.append(
        try JSONDecoder().decode(
          CompanionMemory.self,
          from: VaultSQLConnection.data(row, maximumBytes: 32_768)))
    }
    let started = ContinuousClock.now
    let result = try search.memories(.init(handle: fixture.handle, text: query))
    durations.append(MemoryScaleFixture.seconds(since: started))
    let target = "project_\(index)"
    baselineHits += baseline.contains { $0.key == target } ? 1 : 0
    rankedHits += result.contains { $0.key == target } ? 1 : 0
    #expect(result.count <= 4)
    #expect(result.first?.key == target)
    #expect(result.allSatisfy { !$0.value.contains("foreign") })
  }
  #expect(baselineHits == 0)
  #expect(rankedHits == MemoryScaleFixture.topicCount)
  #expect(try search.memories(.init(handle: fixture.handle, text: "absenttopic")).isEmpty)
  #expect(try search.memories(.init(handle: fixture.handle, text: "\"* OR ( )")).count <= 4)
  let reopened = try ConversationDatabase(directory: fixture.directory)
  var position = CompanionMemoryPageRequest.Position.latest
  var identities = Set<UUID>()
  var pages = 0
  while true {
    let page = try reopened.memoryPage(.init(handle: fixture.handle, position: position))
    #expect(page.facts.count <= CompanionMemoryPageRequest.pageSize)
    for fact in page.facts { #expect(identities.insert(fact.id).inserted) }
    pages += 1
    guard let next = page.next else { break }
    position = .before(next)
  }
  #expect(identities.count == count)
  let slowest = durations.max() ?? 0
  print(
    "MEMORY SCALE facts=\(count) recall=\(rankedHits)/\(MemoryScaleFixture.topicCount) baseline=\(baselineHits) slowestQuerySeconds=\(slowest) pages=\(pages)"
  )
}

@Test func memoryPagingPreservesTiesAndVersionOneFactsAfterMigration() async throws {
  let fixture = try MemoryScaleFixture(count: 200)
  defer { fixture.remove() }
  try fixture.database.sql.execute("DROP INDEX companion_memories_recent")
  try fixture.database.sql.execute("DROP INDEX conversation_messages_date")
  try fixture.database.sql.execute("DROP TABLE personal_facts")
  try fixture.database.sql.execute("DROP TABLE personal_fact_state")
  try fixture.database.sql.execute("DROP TRIGGER memory_embeddings_update")
  try fixture.database.sql.execute("DROP TRIGGER memory_embeddings_delete")
  try fixture.database.sql.execute("DROP TABLE memory_embeddings")
  try fixture.database.sql.execute("PRAGMA user_version=1")
  let reopened = try ConversationDatabase(directory: fixture.directory)
  #expect(try reopened.sql.integer("PRAGMA user_version") == ConversationDatabase.schemaVersion)
  let first = try reopened.memoryPage(.init(handle: fixture.handle))
  let cursor = try #require(first.next)
  let second = try reopened.memoryPage(.init(handle: fixture.handle, position: .before(cursor)))
  let back = try #require(second.previous)
  let previous = try reopened.memoryPage(.init(handle: fixture.handle, position: .after(back)))
  #expect(previous.facts == first.facts)
  #expect(previous.previous == nil)
  let changed = try reopened.clear(fixture.handle)
  #expect(try reopened.memoryPage(.init(handle: changed.handle)).facts.isEmpty)
  #expect(throws: ConversationStorageError.self) {
    try reopened.memoryPage(.init(handle: fixture.handle, position: .before(cursor)))
  }
}

@Test func addingANewerMemoryDoesNotShiftAnExistingPageCursor() async throws {
  let fixture = try MemoryScaleFixture(count: 200)
  defer { fixture.remove() }
  let first = try fixture.database.memoryPage(.init(handle: fixture.handle))
  let next = try #require(first.next)
  let expected = try fixture.database.memoryPage(
    .init(handle: fixture.handle, position: .before(next)))
  let statement = ChatMessage(role: .user, text: "My favorite instrument is the violin.")
  try fixture.database.save(
    .init(handle: fixture.handle, messages: [statement], checkpoint: .init(), savedAt: Date()))
  _ = try fixture.database.remember(
    .init(
      handle: fixture.handle, fact: .init(key: "instrument", value: "violin"),
      source: .init(messageID: statement.id, quote: statement.text), savedAt: Date()))
  let actual = try fixture.database.memoryPage(
    .init(handle: fixture.handle, position: .before(next)))
  #expect(actual.facts == expected.facts)
  #expect(
    try fixture.database.memoryPage(.init(handle: fixture.handle)).facts.first?.key == "instrument")
}

private struct MemoryScaleFixture {
  static let topicCount = 8
  let directory: URL
  let database: ConversationDatabase
  let handle: ConversationHandle

  init(count: Int) throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    database = try ConversationDatabase(directory: directory)
    handle = try database.open(.init(id: "pogo", name: "Pogo")).handle
    let source = ChatMessage(
      role: .user, text: "Synthetic project courier details for storage testing.")
    try database.save(
      .init(handle: handle, messages: [source], checkpoint: .init(), savedAt: .distantPast))
    let rows = MemorySearchFixtureRows(database: database, owner: handle.companionID)
    try database.sql.transaction {
      for index in 0..<count {
        let fact =
          index < Self.topicCount
          ? MemoryFact(key: "project_\(index)", value: "project\(index) courier Selma")
          : MemoryFact(key: "packing_\(index)", value: "courier packing label \(index)")
        let memory = CompanionMemory(
          replacing: nil, fact: fact, source: .init(messageID: source.id, quote: source.text),
          savedAt: Date(timeIntervalSince1970: index < Self.topicCount ? 1 : 2))
        try rows.insertMemory(memory)
        try rows.indexKeywords(memory)
      }
    }
    let other = try database.open(.init(id: "bolt", name: "Bolt")).handle
    let otherSource = ChatMessage(role: .user, text: "Synthetic foreign courier.")
    try database.save(
      .init(handle: other, messages: [otherSource], checkpoint: .init(), savedAt: .distantPast))
    _ = try database.remember(
      .init(
        handle: other, fact: .init(key: "project_0", value: "project0 courier foreign"),
        source: .init(messageID: otherSource.id, quote: otherSource.text), savedAt: .distantFuture))
  }

  static func seconds(since start: ContinuousClock.Instant) -> Double {
    let elapsed = start.duration(to: .now).components
    return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
  }

  func remove() {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }
}
