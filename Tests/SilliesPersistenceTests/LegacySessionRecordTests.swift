import Foundation
import SilliesCore
import SilliesPersistence
import Testing

@Test(arguments: ["legacy-basic", "legacy-audio-permissions", "future-failures"])
func recordRepositoryPreservesFrozenHistoricalFields(_ fixture: String) throws {
  let original = try legacySessionData(fixture)
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeLegacyFixture(directory) }
  let files = VaultFileStorage(directory: directory)
  try files.write(original, named: "sessions.json")
  let repository = SessionRecordRepository(directory: directory)
  let records = try repository.load()
  try repository.save(records)
  #expect(try repository.load() == records)

  let saved = try Data(contentsOf: directory.appendingPathComponent("sessions.json"))
  let oldObjects = try #require(JSONSerialization.jsonObject(with: original) as? [[String: Any]])
  let newObjects = try #require(JSONSerialization.jsonObject(with: saved) as? [[String: Any]])
  #expect(oldObjects.count == newObjects.count)
  for (old, new) in zip(oldObjects, newObjects) {
    let preserved = new.filter { old.keys.contains($0.key) }
    #expect(NSDictionary(dictionary: old) == NSDictionary(dictionary: preserved))
  }
}

@Test func frozenLegacyRecordsDefaultMissingFieldsWithoutInferringPermissionsFromContent() throws {
  let records = try decodeLegacySessions("legacy-basic")
  let record = try #require(records.first)
  #expect(record.kind == .watch)
  #expect(record.id.uuidString == "00000000-0000-0000-0000-000000000001")
  #expect(record.createdAt.ISO8601Format() == "2026-10-25T10:30:00Z")
  #expect(record.imageFilename == "planning.png")
  #expect(record.audioFilename == nil)
  #expect(record.languageIdentifier == nil)
  #expect(record.suggestions.isEmpty)
  #expect(record.explanation.isEmpty)
  #expect(record.processingNote.isEmpty)
  #expect(!record.summaryPending)
  #expect(!record.requiresPermissionAccess)
  #expect(record.failure == nil)
}

@Test func frozenLegacyPermissionErrorsMigrateOnlyRecognizedFailureMarkers() throws {
  let records = try decodeLegacySessions("legacy-audio-permissions")
  let microphone = try #require(records.first { $0.kind == .participate })
  #expect(microphone.failure?.category == .permissionDenied)
  #expect(microphone.failure?.recovery == .openMicrophoneSettings)
  #expect(microphone.audioFilename == "meeting.m4a")
  #expect(microphone.durationSeconds == 125.5)
  #expect(microphone.languageIdentifier == "en-US")
  let snapshot = try #require(records.first { $0.kind == .snap })
  #expect(snapshot.failure?.recovery == .openScreenRecordingSettings)
  let unknown = try #require(records.first { $0.kind == .record })
  #expect(unknown.failure?.category == .unknown)
  #expect(unknown.failureMessage == "An unknown error mentioned system settings.")
  #expect(!unknown.requiresPermissionAccess)
}

@Test func futureSessionFailuresKeepTheirContentWithoutPermissionActions() throws {
  let records = try decodeLegacySessions("future-failures")
  #expect(records.count == 2)
  #expect(records.allSatisfy { !$0.requiresPermissionAccess && !$0.transcript.isEmpty })
  let unknown = try #require(records.first { $0.kind == .listen })
  #expect(unknown.failure?.category == .unknown)
  #expect(unknown.failureMessage == "A newer capture error occurred.")
  let permission = try #require(records.first { $0.kind == .record })
  #expect(permission.failure?.category == .permissionDenied)
  #expect(permission.failure?.recovery == nil)
}

private func legacySessionData(_ name: String) throws -> Data {
  let url = try #require(
    Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
  return try Data(contentsOf: url)
}

private func decodeLegacySessions(_ name: String) throws -> [SessionRecord] {
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  return try decoder.decode([SessionRecord].self, from: legacySessionData(name))
}

private func removeLegacyFixture(_ directory: URL) {
  do { try FileManager.default.removeItem(at: directory) } catch CocoaError.fileNoSuchFile {
    return
  } catch { Issue.record("Could not remove legacy fixture: \(error)") }
}
