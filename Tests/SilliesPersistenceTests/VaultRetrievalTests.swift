import Foundation
import SilliesCore
import SilliesPersistence
import Testing

private func retrievalRecord(text: String) -> SessionRecord {
  SessionRecord(
    kind: .record,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Meeting")),
    content: .init(text: .init(transcript: text)))
}

private func cleanRetrievalFixture(_ directory: URL) {
  do { try FileManager.default.removeItem(at: directory) } catch {
    Issue.record("Fixture cleanup failed: \(error)")
  }
}

@Test func fullTextIndexFindsLateRomanianWordsAndRemovesDeletedRecords() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { cleanRetrievalFixture(directory) }
  let index = try VaultSearchIndex(directory: directory)
  let record = retrievalRecord(
    text: String(repeating: "early words ", count: 8_000) + " Ștefănescu discută îmbunătățirile.")
  try index.synchronize([record])
  #expect(try index.search("stefan imbunatat", kind: .record) == [record.id])
  #expect(try index.search("stefan", kind: .stash).isEmpty)
  #expect(try index.search("\" OR 1=1 --", kind: nil).isEmpty)
  var updated = record
  updated.transcript = "replacement text"
  try index.synchronize([updated])
  #expect(try index.search("stefan", kind: nil).isEmpty)
  #expect(try index.search("replacement", kind: nil) == [record.id])
  try index.synchronize([])
  #expect(try index.search("replacement", kind: nil).isEmpty)
}

@Test func markdownExportIncludesValidatedAttachmentsAndSpeakerNames() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { cleanRetrievalFixture(directory) }
  let source = VaultFileStorage(directory: directory.appendingPathComponent("source"))
  try source.write(Data([1, 2, 3]), named: "capture.png")
  var record = retrievalRecord(text: "[00:00] Meeting · Speaker 1: Ștefan ships API_v2.")
  record.imageFilename = "capture.png"
  let speaker = try #require(SessionSpeakerNaming.speakers(in: record).first)
  record = SessionSpeakerNaming.rename(speaker, to: "Alex", in: record)
  let exporter = VaultMarkdownExporter(sourceDirectory: source.directory)
  let note = try exporter.export(record, to: directory.appendingPathComponent("export"))
  let markdown = try String(contentsOf: note, encoding: .utf8)
  #expect(markdown.contains("Meeting · Alex: Ștefan"))
  #expect(markdown.contains("![Screenshot](capture.png)"))
  #expect(
    try Data(contentsOf: note.deletingLastPathComponent().appendingPathComponent("capture.png"))
      == Data([1, 2, 3]))
  record.audioFilename = "../outside.m4a"
  #expect(throws: (any Error).self) {
    try exporter.export(record, to: directory.appendingPathComponent("bad"))
  }
  #expect(throws: (any Error).self) { try source.attachmentURL(for: "search.sqlite") }
}

@Test func writingHistoryDistinguishesMissingAndCorruptFiles() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { cleanRetrievalFixture(directory) }
  let repository = WritingHistoryRepository(directory: directory)
  #expect(try repository.load().isEmpty)
  let result = WritingResult(
    originalText: "Salut Ștefan", text: "Salut, Ștefan.", applicationName: "Editor")
  try repository.save([result])
  #expect(try repository.load().first?.text == result.text)
  try VaultFileStorage(directory: directory).write(Data("broken".utf8), named: "history.json")
  #expect(throws: (any Error).self) { try repository.load() }
}
