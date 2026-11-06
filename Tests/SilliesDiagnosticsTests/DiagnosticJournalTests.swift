import Foundation
import Testing

@testable import SilliesDiagnostics

private let fixtureTime = Date(timeIntervalSince1970: 1_800_000_000)

@Test func diagnosticsRotateAndExportOnlyBoundedRecentTechnicalEvents() async throws {
  let standard = DiagnosticLimits.standard
  #expect(standard.fileBytes * (standard.fileCount + 1) <= 10_000_000)
  #expect(standard.exportBytes <= 10_000_000 && standard.pendingEvents <= 256)
  let fixture = try DiagnosticFixture()
  defer { fixture.remove() }
  let journal = DiagnosticJournal(directory: fixture.archive, limits: fixture.limits)
  let records = (0..<600).map { sequence in
    DiagnosticRecord(
      event: .init(.chat, .started), launch: fixture.launch,
      sequence: UInt64(sequence), now: fixtureTime)
  }
  try await journal.append(records, now: fixtureTime)
  let entries = try FileManager.default.contentsOfDirectory(
    at: fixture.archive, includingPropertiesForKeys: [.fileSizeKey])
  #expect(entries.count == fixture.limits.fileCount)
  for file in entries {
    #expect(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize! <= fixture.limits.fileBytes)
  }
  try await journal.export(fixture.request())
  let report = try fixture.report()
  #expect(report.events.last?.sequence == 599)
  #expect(try #require(report.events.first).sequence > 0)
  #expect(report.events.map(\.sequence) == report.events.map(\.sequence).sorted())
  #expect(try Data(contentsOf: fixture.export).count <= fixture.limits.exportBytes)
}

@Test func diagnosticsPruneExpiredRecordsWithoutDiscardingRecentEventsInTheSameFile() async throws {
  let fixture = try DiagnosticFixture()
  defer { fixture.remove() }
  let journal = DiagnosticJournal(directory: fixture.archive, limits: fixture.limits)
  let old = fixtureTime.addingTimeInterval(-fixture.limits.retention - 10)
  try await journal.append(
    [
      .init(event: .init(.app, .started), launch: fixture.launch, sequence: 1, now: old),
      .init(event: .init(.chat, .started), launch: fixture.launch, sequence: 2, now: fixtureTime),
    ], now: old)
  let restarted = DiagnosticJournal(directory: fixture.archive, limits: fixture.limits)
  try await restarted.export(fixture.request())
  #expect(try fixture.report().events.map(\.sequence) == [2])
  let data = try Data(contentsOf: fixture.archive.appendingPathComponent("events-0.jsonl"))
  #expect(!String(decoding: data, as: UTF8.self).contains("\"sequence\":1"))
}

@Test func diagnosticsRecoverPartialWritesAndRejectPrivateErrorContext() async throws {
  let fixture = try DiagnosticFixture()
  defer { fixture.remove() }
  let journal = DiagnosticJournal(directory: fixture.archive, limits: fixture.limits)
  let privateError = NSError(
    domain: "/Users/private/secret", code: 42,
    userInfo: [
      NSLocalizedDescriptionKey: "my private transcript", "prompt": "private vault text",
    ])
  let event = DiagnosticEvent(.synthesis, .failed).failing(privateError)
    .using(model: "/Users/private/model", provider: "pocket-tts")
  try await journal.append(
    [
      .init(event: event, launch: fixture.launch, sequence: 1, now: fixtureTime)
    ], now: fixtureTime)
  let file = fixture.archive.appendingPathComponent("events-0.jsonl")
  let handle = try FileHandle(forWritingTo: file)
  try handle.seekToEnd()
  try handle.write(contentsOf: Data("{\"incomplete\":".utf8))
  try handle.close()
  try Data("abandoned staging file".utf8).write(
    to: fixture.archive.appendingPathComponent("pruning.pending"))
  let restarted = DiagnosticJournal(directory: fixture.archive, limits: fixture.limits)
  try await restarted.export(fixture.request())
  let report = try fixture.report()
  #expect(report.events.count == 1 && report.invalidRecords == 1)
  #expect(report.events.first?.event.failure?.code == 42)
  #expect(report.events.first?.event.model == nil)
  let text = try String(contentsOf: fixture.export, encoding: .utf8)
  for secret in ["private", "secret", "transcript", "prompt", "incomplete"] {
    #expect(!text.contains(secret))
  }
  #expect(
    !FileManager.default.fileExists(
      atPath: fixture.archive.appendingPathComponent("pruning.pending").path))
}

@Test func diagnosticsRejectSymlinksAndInvalidRetentionLimits() async throws {
  let fixture = try DiagnosticFixture()
  defer { fixture.remove() }
  try FileManager.default.createDirectory(at: fixture.archive, withIntermediateDirectories: true)
  try Data("unrelated private file".utf8).write(to: fixture.export)
  try FileManager.default.createSymbolicLink(
    at: fixture.archive.appendingPathComponent("events-0.jsonl"), withDestinationURL: fixture.export
  )
  let journal = DiagnosticJournal(directory: fixture.archive, limits: fixture.limits)
  await #expect(throws: (any Error).self) { try await journal.prepare(now: fixtureTime) }
  #expect(try String(contentsOf: fixture.export, encoding: .utf8) == "unrelated private file")
  var limits = fixture.limits
  limits.fileBytes = .max
  #expect(throws: DiagnosticStorageError.self) { try limits.validate() }
}

struct DiagnosticFixture {
  let directory: URL
  let launch = UUID()
  var archive: URL { directory.appendingPathComponent("archive") }
  var export: URL { directory.appendingPathComponent("report.json") }
  var limits: DiagnosticLimits {
    var limits = DiagnosticLimits.standard
    limits.fileBytes = 2_048
    limits.fileCount = 3
    limits.exportBytes = 6_144
    return limits
  }
  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  func request() -> DiagnosticJournal.ExportRequest {
    .init(destination: export, environment: .init(), droppedEvents: 0, now: fixtureTime)
  }
  struct Report: Decodable {
    let events: [DiagnosticRecord]
    let invalidRecords: Int
  }
  func report() throws -> Report {
    try DiagnosticRecord.decoder().decode(Report.self, from: Data(contentsOf: export))
  }
  func remove() {
    do { try FileManager.default.removeItem(at: directory) } catch {
      fputs("Diagnostic fixture cleanup failed: \(error)\n", stderr)
    }
  }
}
