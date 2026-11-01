import Foundation
import Synchronization
import Testing

@testable import SilliesTextModels

private struct TextStreamFixture {
  enum Pace { case immediate, delayed }
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "text-stream-worker-\(UUID())")
  let preparation = TextModelPreparation(
    directory: URL(fileURLWithPath: "/tmp/unused-stream-model"), contextTokens: 4_096,
    memoryLimitBytes: TextModelMemoryBudget.gibibyte)
  let request = TextGenerationRequest(instructions: "Reply", prompt: "Hello", maximumTokens: 50)
  init(finalText: String, pace: Pace = .immediate) throws {
    let pause = pace == .delayed ? "/bin/sleep 0.2" : ""
    let message = TextInferenceRequest(configuration: preparation, generation: request)
    let count = try JSONEncoder().encode(message).count + 4
    let first = try Self.frame(TextInferenceEvent.delta("Hello "))
    let second = try Self.frame(TextInferenceEvent.delta("Ștefan 👋🏽"))
    let final = try Self.frame(TextInferenceEvent.finished(.init(output: .init(text: finalText))))
    let script = """
      #!/bin/sh
      /bin/dd bs=1 count=\(count) of=/dev/null 2>/dev/null
      printf '\(first)'
      /bin/dd bs=1 count=6 of=/dev/null 2>/dev/null
      \(pause)
      printf '\(second)'
      /bin/dd bs=1 count=6 of=/dev/null 2>/dev/null
      \(pause)
      printf '\(final)'
      """
    try Data(script.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
  }
  private static func frame<T: Encodable>(_ value: T) throws -> String {
    let data = try JSONEncoder().encode(value)
    var size = UInt32(data.count).bigEndian
    var frame = withUnsafeBytes(of: &size) { Data($0) }
    frame.append(data)
    return frame.map { String(format: "\\%03o", $0) }.joined()
  }
  func remove() {
    do { try FileManager.default.removeItem(at: url) } catch {
      Issue.record("Stream fixture cleanup: \(error)")
    }
  }
}

@Test func streamDeadlineIsNotRenewedByEveryNewToken() async throws {
  let fixture = try TextStreamFixture(finalText: "Hello Ștefan 👋🏽", pace: .delayed)
  defer { fixture.remove() }
  let connection = try TextWorkerConnection(executable: fixture.url, responseTimeout: 0.3)
  await #expect(throws: (any Error).self) {
    try await connection.stream(
      .init(configuration: fixture.preparation, generation: fixture.request), receive: { _ in })
  }
  connection.stop()
  await connection.reap()
}

@Test func textWorkerStreamsAcknowledgedDeltasBeforeReturningItsFinalResult() async throws {
  let fixture = try TextStreamFixture(finalText: "Hello Ștefan 👋🏽")
  defer { fixture.remove() }
  let model = try await MLXTextModelProvider(executable: fixture.url).prepare(fixture.preparation)
  let deltas = Mutex<[String]>([])
  let result = try await model.stream(fixture.request) { delta in
    deltas.withLock { $0.append(delta) }
  }
  #expect(deltas.withLock { $0 } == ["Hello ", "Ștefan 👋🏽"])
  #expect(result.text == "Hello Ștefan 👋🏽")
  await model.stop()
}

@Test func textWorkerRejectsAFinalResultThatRewritesAlreadyDeliveredText() async throws {
  let fixture = try TextStreamFixture(finalText: "An unrelated answer")
  defer { fixture.remove() }
  let model = try await MLXTextModelProvider(executable: fixture.url).prepare(fixture.preparation)
  await #expect(throws: TextModelError.self) {
    try await model.stream(fixture.request, receive: { _ in })
  }
  await model.stop()
}
