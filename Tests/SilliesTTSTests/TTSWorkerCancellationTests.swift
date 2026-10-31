import Foundation
import SilliesTTS
import Testing

@Test func cancellingStalledVoiceWorkerReleasesTheProcessPromptly() async throws {
  let script = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sillies-stalled-voice-worker-\(UUID())")
  try Data("#!/bin/sh\nexec /bin/sleep 30\n".utf8).write(to: script)
  try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
  defer {
    do { try FileManager.default.removeItem(at: script) } catch {
      Issue.record("Voice fixture cleanup: \(error)")
    }
  }
  let runtime = try await WorkerTTSProvider(id: "fixture", executable: script).prepare(
    .init(
      directory: URL(fileURLWithPath: "/tmp/unused-voice"), providerID: "fixture", variant: "test"))
  let generation = Task {
    try await runtime.synthesize(.init(text: "Hello", voiceID: "voice", language: "en")) { _ in }
  }
  try await Task.sleep(for: .milliseconds(100))
  let started = ContinuousClock.now
  generation.cancel()
  await #expect(throws: (any Error).self) { try await generation.value }
  await runtime.stop()
  #expect(started.duration(to: .now) < .seconds(2))
}
