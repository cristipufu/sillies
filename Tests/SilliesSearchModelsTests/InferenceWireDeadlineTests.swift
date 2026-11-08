import Foundation
import SilliesCore
import SilliesInference
import Testing

@testable import SilliesSearchModels

@Test func inferenceWireReadDeadlineIsATimeoutRatherThanAnInterruption() throws {
  let pipe = Pipe()
  do {
    _ = try InferenceWire.read(
      String.self, from: pipe.fileHandleForReading,
      deadline: ProcessInfo.processInfo.systemUptime + 0.01)
    Issue.record("An idle pipe must not complete a read.")
  } catch InferenceWorkerError.timedOut {}
}

@Test func inferenceWireExpiredWriteIsATimeout() throws {
  let pipe = Pipe()
  do {
    try InferenceWire.write(
      "fixture", to: pipe.fileHandleForWriting, deadline: ProcessInfo.processInfo.systemUptime - 1)
    Issue.record("An expired write must not be sent.")
  } catch InferenceWorkerError.timedOut {}
}

@Test func inferenceWireClosedPipeRemainsAnInterruption() throws {
  let pipe = Pipe()
  try pipe.fileHandleForWriting.close()
  do {
    _ = try InferenceWire.read(
      String.self, from: pipe.fileHandleForReading,
      deadline: ProcessInfo.processInfo.systemUptime + 1)
    Issue.record("A closed pipe must not complete a read.")
  } catch InferenceWorkerError.interrupted {}
}

@Test func embeddingWorkerReportsItsDeadlineAndCanPrepareAgain() async throws {
  let executable = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: executable) } catch { Issue.record(error) } }
  let response = try JSONEncoder().encode(EmbeddingResponse(identity: "fixture"))
  var length = UInt32(response.count).bigEndian
  let frame = withUnsafeBytes(of: &length) { Data($0) } + response
  let escaped = frame.map { String(format: "\\%03o", $0) }.joined()
  try Data("#!/bin/sh\nprintf '\(escaped)'\nexec /bin/sleep 30\n".utf8).write(to: executable)
  try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
  let session = EmbeddingWorkerSession(
    configuration: .init(provider: "apple", identity: "fixture", directory: nil),
    executable: executable, modelBytes: 1, activity: InferenceActivity())
  do {
    let access = try await session.access()
    do {
      _ = try await access.embed(.init(text: "fixture", purpose: .query))
      Issue.record("The stalled helper must not produce an embedding.")
    } catch SearchEmbeddingError.timedOut {}
    #expect(try await session.access().identity == "fixture")
    await session.stop()
  } catch {
    await session.stop()
    throw error
  }
}
