import Foundation
import SilliesCore
import Testing

@testable import SilliesVault

@Test func explicitVaultSelectionReadsCurrentRecordsAndKeepsRelevantExcerpt() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let library = VaultLibrary(directory: directory)
  var record = SessionRecord(
    kind: .stash,
    origin: .init(
      characterID: "pogo", characterName: "Pogo", source: .init(appName: "Aurora notes")))
  record.stashedItems = [
    String(repeating: "Earlier notes. ", count: 80) + "The delivery code is quartz-42."
  ]
  _ = try await library.commit(.init(records: [.insert(record)]))
  var selection = ConversationRecordSelection()
  try selection.add(record.id)
  let result = try await library.selectedRecords(selection, query: "delivery code")
  #expect(result.first?.source?.excerpt.contains("quartz-42") == true)
  #expect(
    (result.first?.source?.excerpt.count ?? .max)
      <= ConversationRecordContext.maximumExcerptCharacters)
  #expect(result.first?.isComplete == false)
  _ = try await library.commit(.init(deletion: .records([record.id])))
  let removed = try await library.selectedRecords(selection, query: "delivery code")
  #expect(removed.first?.id == record.id)
  #expect(removed.first?.isAvailable == false)
  #expect(removed.first?.source == nil)
}
