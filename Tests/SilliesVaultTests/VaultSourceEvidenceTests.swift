import Foundation
import SilliesCore
import SilliesPersistence
import Testing

@testable import SilliesVault

@Test func vaultSourceEvidencePreservesSeparateLatePassagesAndAttachedContext() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let library = VaultLibrary(directory: directory)
  let body =
    "Budget: 900 credits. " + String(repeating: "Unrelated discussion. ", count: 400)
    + "Deadline: Thursday."
  var record = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Meeting")),
    content: .init(text: .init(transcript: body)))
  record.audioFilename = "fixture.m4a"
  record.transcriptSegments = [
    .init(sequence: 0, source: "application", start: 522, end: 540, text: "Budget: 900 credits.")
  ]
  _ = try await library.commit(.init(records: [.insert(record)]))
  let arguments = try JSONEncoder().encode([
    "recordID": record.id.uuidString, "query": "budget deadline",
  ])
  let result = try await VaultReadTool(library: library).call(arguments: arguments)
  let source = try #require(result.sources.first)
  #expect(source.passages.contains { $0.text.contains("900 credits") })
  #expect(source.passages.contains { $0.text.contains("Thursday") })
  #expect(source.hasRecording)
  for passage in source.passages { #expect(try await library.evidenceLocation(passage) != nil) }
  var selection = ConversationRecordSelection()
  try selection.add(record.id)
  let context = try await library.selectedRecords(selection, query: "deadline")
  let selected = try #require(context.first?.source)
  #expect(selected.excerpt.contains("Thursday"))
  #expect(!selected.passages.isEmpty)
  #expect(selected.passages.allSatisfy { selected.excerpt.contains($0.text) })
  let search = try await VaultSearchTool(library: library).call(
    arguments: Data(#"{"query":"deadline","category":"meetings"}"#.utf8))
  let searched = try #require(search.sources.first)
  #expect(searched.excerpt.contains("Thursday"))
  #expect(!searched.passages.isEmpty)
  for passage in searched.passages { #expect(try await library.evidenceLocation(passage) != nil) }
}

@Test func vaultSourceEvidenceKeepsAuthoredNotesInTheirOwnSection() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let library = VaultLibrary(directory: directory)
  let record = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Meeting")),
    content: .init(text: .init(transcript: "The recorded discussion.")))
  let header = try await library.createDocument(
    record: record,
    metadata: .init(kind: .capture, title: "Planning", modifiedAt: Date()),
    notes: "My annotation: check compliance.")
  let args = try JSONEncoder().encode(["recordID": header.id.uuidString, "query": "compliance"])
  let output = try await VaultReadTool(library: library).call(arguments: args)
  let evidence = output.sources.flatMap(\.passages)
  #expect(
    evidence.contains { $0.reference.location.section == .notes && $0.text.contains("compliance") })
  for passage in evidence { #expect(try await library.evidenceLocation(passage) != nil) }
}

@Test func vaultSourceEvidenceUsesCurrentAuthoredTextBeforeGeneratedSummary() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let library = VaultLibrary(directory: directory)
  var record = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Notes")))
  record.summary = "Obsolete summary: Tuesday."
  let header = try await library.createDocument(
    record: record,
    metadata: .init(kind: .note, title: "Schedule", modifiedAt: Date()),
    notes: "Current decision: Thursday.")
  let args = try JSONEncoder().encode(["recordID": header.id.uuidString, "query": "decision"])
  let output = try await VaultReadTool(library: library).call(arguments: args)
  #expect(output.sources.first?.excerpt == "Current decision: Thursday.")
  #expect(output.sources.first?.passages.first?.reference.location.section == .notes)
  #expect(!output.text.contains("Tuesday"))
}

@Test func vaultSourceEvidenceKeepsMetadataMatchesAsRecordLevelSources() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let library = VaultLibrary(directory: directory)
  let record = SessionRecord(
    kind: .listen,
    origin: .init(
      characterID: "pogo", characterName: "Pogo", source: .init(appName: "SpectralRoster")),
    content: .init(text: .init(transcript: "Unrelated recorded text.")))
  _ = try await library.commit(.init(records: [.insert(record)]))
  let result = try await VaultSearchTool(library: library).call(
    arguments: Data(#"{"query":"SpectralRoster","category":"all"}"#.utf8))
  let source = try #require(result.sources.first)
  #expect(source.id == record.id)
  #expect(source.passages.isEmpty)
  #expect(source.excerpt.contains("SpectralRoster"))
}
