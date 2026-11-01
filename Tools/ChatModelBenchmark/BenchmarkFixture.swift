import Foundation
import SilliesCore
import SilliesVault

struct BenchmarkFixture {
  private static let date = Date(timeIntervalSince1970: 1_793_491_200)
  let directory: URL
  let vault: VaultLibrary
  let conversations: ConversationLibrary
  let handle: ConversationHandle

  static func create(for scenario: BenchmarkScenario, root: URL) async throws -> Self {
    let directory = root.appendingPathComponent(
      "sillies-chat-eval-\(UUID())")
    let vault = VaultLibrary(directory: directory)
    let conversations = ConversationLibrary(directory: directory)
    do {
      let opened = try await conversations.open(
        .init(id: scenario.owner.id, name: scenario.owner.name))
      let fixture = Self(
        directory: directory, vault: vault, conversations: conversations, handle: opened.handle)
      try await fixture.seed(scenario)
      try await fixture.verify(scenario)
      return fixture
    } catch {
      remove(directory)
      throw error
    }
  }

  func remove() { Self.remove(directory) }
  private static func remove(_ directory: URL) {
    do {
      if FileManager.default.fileExists(atPath: directory.path) {
        try FileManager.default.removeItem(at: directory)
      }
    } catch { fputs("Benchmark fixture cleanup failed: \(error)\n", stderr) }
  }

  func save(_ messages: [ChatMessage], memory: ConversationMemory) async throws {
    try await conversations.save(
      .init(
        handle: handle, messages: messages, checkpoint: .init(memory: memory), savedAt: Self.date))
  }

  private func seed(_ scenario: BenchmarkScenario) async throws {
    let records = scenario.records.map { record in
      SessionRecord(
        kind: record.kind,
        origin: .init(
          characterID: scenario.owner.id, characterName: scenario.owner.name,
          source: .init(appName: record.app, windowTitle: record.title)),
        content: .init(
          text: .init(
            transcript: record.kind == .listen || record.kind == .participate ? record.text : "",
            extractedText: record.kind == .snap ? record.text : "",
            stashedItems: record.links.isEmpty && record.kind == .stash
              ? [record.text] : record.links),
          notes: .init(summary: record.title),
          attachments: .init(
            imageFilename: record.kind == .snap ? "\(record.id).png" : nil)),
        metadata: .init(id: record.id, createdAt: Self.date))
    }
    for record in records {
      if let filename = record.imageFilename {
        try BenchmarkImageFixture.write(to: directory.appendingPathComponent(filename))
      }
    }
    if !records.isEmpty { _ = try await vault.commit(.init(records: records.map { .insert($0) })) }
    for fact in scenario.memories {
      let source = ChatMessage(role: .user, text: fact.statement)
      try await save([source], memory: .init())
      _ = try await conversations.remember(
        .init(
          handle: handle, fact: .init(key: fact.key, value: fact.value),
          source: .init(messageID: source.id, quote: source.text), savedAt: Self.date))
    }
  }

  private func verify(_ scenario: BenchmarkScenario) async throws {
    for record in scenario.records {
      guard try await vault.record(id: record.id) != nil else {
        throw BenchmarkFixtureError.missingRecord(record.id)
      }
      if record.kind == .snap {
        let matches = try await vault.search(.init(query: record.app, category: .screenshots))
        guard matches.contains(where: { $0.header.id == record.id }) else {
          throw BenchmarkFixtureError.missingScreenshot(record.id)
        }
      }
    }
  }
}

private enum BenchmarkFixtureError: Error {
  case missingRecord(UUID)
  case missingScreenshot(UUID)
}
