import Foundation
import SilliesCore
import Testing

@testable import SilliesVault

@Test(arguments: ["release recovery", "recovery release", "RELEASE release recovery"])
func vaultPassagesRankAllQueryTermsAcrossTheCapturedText(_ query: String) throws {
  let body =
    "Release planning started. " + String(repeating: "Earlier unrelated discussion. ", count: 200)
    + "The release recovery identifier is quartz-73, owned by Leena."
  var record = passageRecord(body)
  record.summary = "The release recovery identifier is obsolete."
  let passage = try VaultRecordPassage.select(in: record, query: query)
  #expect(passage.text.contains("quartz-73"))
  #expect(!passage.text.contains("obsolete"))
  #expect(!passage.coverage.isComplete)
  #expect(passage.coverage.startOffset > 0)
  #expect(passage.text.count <= VaultRecordPassage.maximumCharacters)

  record.transcript = "Release planning started."
  record.stashedItems = [body]
  #expect(try VaultRecordPassage.select(in: record, query: query).text.contains("quartz-73"))
}

@Test func vaultPassageContinuationPreservesUnicodeWithoutGapsOrDuplicates() throws {
  let body = String(repeating: "Ședință 👩🏽‍💻 café e\u{301}. ", count: 200)
  let record = passageRecord(body)
  var next: Int? = 0
  var reconstructed = ""
  while let offset = next {
    let passage = try VaultRecordPassage.select(in: record, query: "ignored", offset: offset)
    #expect(passage.coverage.startOffset == reconstructed.count)
    #expect(passage.coverage.totalCharacters == body.count)
    reconstructed += passage.text
    next = passage.coverage.nextOffset
  }
  #expect(reconstructed == body)
  for offset in [-1, Int.min, Int.max, body.count + 1] {
    #expect(throws: VaultRecordPassage.SelectionError.self) {
      try VaultRecordPassage.select(in: record, query: "", offset: offset)
    }
  }
  #expect(try VaultRecordPassage.select(in: record, query: "", offset: body.count).text.isEmpty)
  #expect(try VaultRecordPassage.select(in: passageRecord(""), query: "").coverage.isComplete)
}

@Test func vaultRecordReadReportsActualFullAndRecoveryPassageCoverage() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let library = VaultLibrary(directory: directory)
  let body = String(repeating: "An earlier discussion. ", count: 200) + "Final handoff to Leena."
  let record = passageRecord(body)
  _ = try await library.commit(.init(records: [.insert(record)]))
  let tool = VaultReadTool(library: library)
  let arguments = try JSONEncoder().encode(["recordID": record.id.uuidString, "query": ""])
  let output = try await tool.call(arguments: arguments)
  let decoder = JSONDecoder()
  let full = try decoder.decode(ReadResult.self, from: Data(output.text.utf8))
  let brief = try decoder.decode(ReadResult.self, from: Data(output.briefText.utf8))
  for result in [full, brief] {
    #expect(result.record.recordID == record.id)
    #expect(result.coverage.startOffset == 0)
    #expect(result.coverage.endOffset == result.record.excerpt.count)
    #expect(result.coverage.nextOffset == result.coverage.endOffset)
    #expect(result.coverage.totalCharacters == body.count)
    #expect(!result.coverage.isComplete)
  }
  #expect(brief.record.excerpt.count < full.record.excerpt.count)
  let next = try #require(full.coverage.nextOffset)
  let continuation = try JSONSerialization.data(withJSONObject: [
    "recordID": record.id.uuidString, "query": "", "offset": next,
  ])
  let continued = try await tool.call(arguments: continuation)
  let result = try decoder.decode(ReadResult.self, from: Data(continued.text.utf8))
  #expect(result.coverage.startOffset == next)
  #expect(
    result.record.excerpt
      == String(body.dropFirst(next).prefix(VaultRecordPassage.maximumCharacters)))
}

private func passageRecord(_ text: String) -> SessionRecord {
  .init(
    kind: .listen,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Meeting")),
    content: .init(text: .init(transcript: text)))
}

private struct ReadResult: Decodable {
  struct Record: Decodable {
    let recordID: UUID
    let excerpt: String
  }
  struct Coverage: Decodable {
    let startOffset: Int
    let endOffset: Int
    let totalCharacters: Int
    let nextOffset: Int?
    let isComplete: Bool
  }
  let record: Record
  let coverage: Coverage
}
