import AppKit
import SilliesCore
import SilliesPersistence
import SilliesWriting
import Testing

@testable import SilliesApp

@Test @MainActor func writingHistoryFlushReportsFailureAndRetryDuringModalTermination() async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let history = WritingHistory(directory: directory)
  await history.load()
  let blocker = directory.appendingPathComponent("history.json")
  try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
  history.save(.init(originalText: "Keep this", text: "Keep this", applicationName: "Editor"))
  var receipt: Result<Void, WritingHistoryFailure>?
  history.flush { receipt = $0 }
  pumpWritingTermination { receipt != nil }
  if case .failure(.save) = receipt {
  } else {
    Issue.record("Modal flush must deliver the write failure")
  }
  try FileManager.default.removeItem(at: blocker)
  receipt = nil
  history.retry()
  history.flush { receipt = $0 }
  pumpWritingTermination { receipt != nil }
  try #require(receipt).get()
  #expect(try WritingHistoryRepository(directory: directory).load().first?.text == "Keep this")
}

@MainActor private func pumpWritingTermination(_ finished: () -> Bool) {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: .seconds(3))
  while !finished(), clock.now < deadline {
    CFRunLoopRunInMode(CFRunLoopMode(RunLoop.Mode.modalPanel.rawValue as CFString), 0.01, true)
  }
}
