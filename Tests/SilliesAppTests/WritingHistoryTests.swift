import Foundation
import SilliesCore
import SilliesPersistence
import Testing

@testable import SilliesApp

@Test @MainActor func writingHistoryMergesEarlyResultsAndNeverOverwritesCorruptStorage()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let files = VaultFileStorage(directory: directory)
  let broken = Data("broken history".utf8)
  try files.write(broken, named: "history.json")
  let history = WritingHistory(directory: directory)
  await history.load()
  let fresh = WritingResult(originalText: "new", text: "new", applicationName: "Editor")
  history.save(fresh)
  await history.flush()
  #expect(history.error != nil)
  #expect(try Data(contentsOf: files.url(for: "history.json")) == broken)
  let old = WritingResult(originalText: "old", text: "old", applicationName: "Editor")
  try WritingHistoryRepository(directory: directory).save([old])
  await history.load()
  await history.flush()
  #expect(history.error == nil)
  #expect(Set(history.results.map(\.id)) == [old.id, fresh.id])
  history.clear()
  await history.flush()
  #expect(try WritingHistoryRepository(directory: directory).load().isEmpty)
}

@Test @MainActor func writingRecoveryRemainsBoundedAndSeparateFromMeetings() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let history = WritingHistory(directory: directory)
  await history.load()
  for number in 0..<100 {
    history.save(.init(originalText: "\(number)", text: "\(number)", applicationName: "Editor"))
  }
  await history.flush()
  let saved = try WritingHistoryRepository(directory: directory).load()
  #expect(saved.count == WritingHistory.maximumResults)
  #expect(saved.first?.text == "99")
  #expect(
    !FileManager.default.fileExists(atPath: directory.appendingPathComponent("sessions.json").path))
}
