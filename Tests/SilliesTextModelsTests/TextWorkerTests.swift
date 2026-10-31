import Foundation
import Testing

@testable import SilliesTextModels

@Test func workerExitIsRecoverableAndRequestsRemainBounded() async throws {
  let provider = MLXTextModelProvider(executable: URL(fileURLWithPath: "/usr/bin/false"))
  let runtime = try await provider.prepare(
    .init(directory: URL(fileURLWithPath: "/tmp/absent-text-model"), contextTokens: 4096))
  for _ in 0..<2 {
    await #expect(throws: (any Error).self) {
      try await runtime.generate(
        .init(instructions: "Summarize", prompt: "Salut!", maximumTokens: 50))
    }
  }
  await runtime.stop()
  let pipe = Pipe()
  #expect(throws: TextModelError.self) {
    try TextInferenceWire.write(
      String(repeating: "a", count: TextInferenceWire.maximumMessageBytes + 1),
      to: pipe.fileHandleForWriting, deadline: ProcessInfo.processInfo.systemUptime + 1)
  }
}

@Test func truncatedAndOversizedFramesAreRejectedBeforeAllocation() throws {
  for header in [Data([0xff, 0xff, 0xff, 0xff]), Data([0, 0, 0, 16, 123])] {
    let pipe = Pipe()
    try pipe.fileHandleForWriting.write(contentsOf: header)
    try pipe.fileHandleForWriting.close()
    #expect(throws: (any Error).self) {
      try TextInferenceWire.read(
        TextInferenceResponse.self, from: pipe.fileHandleForReading,
        deadline: ProcessInfo.processInfo.systemUptime + 1)
    }
  }
}

@Test(arguments: 0..<12) func cancellingAnUnresponsiveWorkerReleasesTheCallerAndProcess(
  attempt: Int
) async throws {
  let script = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sillies-stalled-text-worker-\(attempt)-\(UUID())")
  try Data("#!/bin/sh\nexec /bin/sleep 30\n".utf8).write(to: script)
  try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
  defer {
    do { try FileManager.default.removeItem(at: script) } catch {
      Issue.record("Worker fixture cleanup: \(error)")
    }
  }
  let runtime = try await MLXTextModelProvider(executable: script).prepare(
    .init(directory: URL(fileURLWithPath: "/tmp/unused-model"), contextTokens: 4096))
  let generation = Task {
    try await runtime.generate(
      .init(instructions: "Summarize", prompt: "Salut!", maximumTokens: 50))
  }
  try await Task.sleep(for: .milliseconds(100))
  let started = ContinuousClock.now
  generation.cancel()
  await #expect(throws: (any Error).self) { try await generation.value }
  #expect(started.duration(to: .now) < .seconds(2))
  await runtime.stop()
}
