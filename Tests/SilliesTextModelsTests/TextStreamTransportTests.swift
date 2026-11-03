import Foundation
import SilliesModelStore
import Synchronization
import Testing

@testable import SilliesTextModels

private struct TextStreamFixture {
  enum Pace { case immediate, delayed }
  enum ReleaseResponse { case acknowledge, delayedAcknowledgement, exit }
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "text-stream-worker-\(UUID())")
  let preparation: TextModelPreparation
  let request: TextGenerationRequest
  var releasedFrame: URL { url.appendingPathExtension("release") }
  init(
    finalText: String, pace: Pace = .immediate, session: UUID? = nil,
    releaseResponse: ReleaseResponse = .acknowledge
  ) throws {
    try self.init(
      final: .init(output: .init(text: finalText)), pace: pace, session: session,
      releaseResponse: releaseResponse)
  }
  init(failure: TextGenerationFailure) throws {
    try self.init(
      final: .init(failure: failure.localizedDescription, generationFailure: failure),
      pace: .immediate, session: nil, releaseResponse: .acknowledge)
  }
  private init(
    final response: TextInferenceResponse, pace: Pace, session: UUID?,
    releaseResponse: ReleaseResponse
  ) throws {
    preparation = TextModelPreparation(
      directory: URL(fileURLWithPath: "/tmp/unused-stream-model"),
      profile: try TextModelCatalog.bundled().manifests[0].model.profile,
      memoryLimitBytes: TextModelMemoryBudget.gibibyte)
    request = TextGenerationRequest(instructions: "Reply", prompt: "Hello", maximumTokens: 50)
      .inSession(session)

    let pause = pace == .delayed ? "/bin/sleep 0.2" : ""
    let message = TextInferenceRequest(configuration: preparation, generation: request)
    let count = try JSONEncoder().encode(message).count + 4
    let first = try Self.frame(TextInferenceEvent.delta("Hello "))
    let second = try Self.frame(TextInferenceEvent.delta("Ștefan 👋🏽"))
    let final = try Self.frame(TextInferenceEvent.finished(response))
    let release: String
    if let session {
      let command = TextInferenceRequest(
        configuration: preparation, generation: .releasingSession(session))
      let bytes = try JSONEncoder().encode(command).count + 4
      let completion = try Self.frame(TextInferenceEvent.finished(.init(output: .init(text: ""))))
      let acknowledgement = releaseResponse == .exit ? "exit 0" : "printf '\(completion)'"
      let delay = releaseResponse == .delayedAcknowledgement ? "/bin/sleep 0.15" : ""
      release = """
        /bin/dd bs=1 count=\(bytes) of='\(releasedFrame.path)' 2>/dev/null
        \(delay)
        \(acknowledgement)
        """
    } else {
      release = ""
    }
    let exchange = """
      /bin/dd bs=1 count=\(count) of=/dev/null 2>/dev/null
      printf '\(first)'
      /bin/dd bs=1 count=6 of=/dev/null 2>/dev/null
      \(pause)
      printf '\(second)'
      /bin/dd bs=1 count=6 of=/dev/null 2>/dev/null
      \(pause)
      printf '\(final)'
      """
    let followup = releaseResponse == .delayedAcknowledgement ? exchange : ""
    let script = """
      #!/bin/sh
      \(exchange)
      \(release)
      \(followup)
      """
    try Data(script.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
  }
  func waitForRelease() async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !FileManager.default.fileExists(atPath: releasedFrame.path) {
      guard ContinuousClock.now < deadline else { throw TextModelError.interrupted }
      try await Task.sleep(for: .milliseconds(5))
    }
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
    if FileManager.default.fileExists(atPath: releasedFrame.path) {
      do { try FileManager.default.removeItem(at: releasedFrame) } catch {
        Issue.record("Release fixture cleanup: \(error)")
      }
    }
  }
}

@Test func aNewConversationWaitsForPendingIdleCleanupInsteadOfFailingBusy() async throws {
  let id = UUID()
  let fixture = try TextStreamFixture(
    finalText: "Hello Ștefan 👋🏽", session: id, releaseResponse: .delayedAcknowledgement)
  defer { fixture.remove() }
  let model = try await MLXTextModelProvider(executable: fixture.url).prepare(fixture.preparation)
  _ = try await model.complete(fixture.request)
  let cleanup = Task { await model.releaseConversation(id) }
  do {
    try await fixture.waitForRelease()
    let next = try await model.complete(fixture.request.inSession(UUID()))
    #expect(next.text == "Hello Ștefan 👋🏽")
    await cleanup.value
    await model.stop()
  } catch {
    await model.stop()
    await cleanup.value
    throw error
  }
}

@Test func conversationCleanupFailurePreservesTheAlreadyCompletedReply() async throws {
  let id = UUID()
  let fixture = try TextStreamFixture(
    finalText: "Hello Ștefan 👋🏽", session: id, releaseResponse: .exit)
  defer { fixture.remove() }
  let model = try await MLXTextModelProvider(executable: fixture.url).prepare(fixture.preparation)
  let result = try await model.stream(fixture.request) { _ in
    await model.releaseConversation(id)
  }
  #expect(result.text == "Hello Ștefan 👋🏽")
  #expect(FileManager.default.fileExists(atPath: fixture.releasedFrame.path))
  await model.stop()
}

@Test func anIdleConversationCanReleaseNativeStateWithoutStoppingItsModel() async throws {
  let id = UUID()
  let fixture = try TextStreamFixture(finalText: "Hello Ștefan 👋🏽", session: id)
  defer { fixture.remove() }
  let model = try await MLXTextModelProvider(executable: fixture.url).prepare(fixture.preparation)
  _ = try await model.complete(fixture.request)
  await model.releaseConversation(id)
  let frame = try Data(contentsOf: fixture.releasedFrame)
  let command = try JSONDecoder().decode(TextInferenceRequest.self, from: frame.dropFirst(4))
  #expect(command.generation.sessionID == id)
  await model.stop()
}

@Test func endingAConversationDuringStreamingWaitsForTheFinalReceiptBeforeReleasingNativeState()
  async throws
{
  let id = UUID()
  let fixture = try TextStreamFixture(finalText: "Hello Ștefan 👋🏽", session: id)
  defer { fixture.remove() }
  let model = try await MLXTextModelProvider(executable: fixture.url).prepare(fixture.preparation)
  let result = try await model.stream(fixture.request) { _ in
    await model.releaseConversation(id)
  }
  #expect(result.text == "Hello Ștefan 👋🏽")
  let frame = try Data(contentsOf: fixture.releasedFrame)
  let command = try JSONDecoder().decode(TextInferenceRequest.self, from: frame.dropFirst(4))
  #expect(command.generation.operation == .releaseSession)
  #expect(command.generation.sessionID == id)
  await model.stop()
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
  await #expect(throws: TextGenerationFailure.self) {
    try await model.stream(fixture.request, receive: { _ in })
  }
  await model.stop()
}

@Test func textWorkerPreservesTheNativeFailureReasonAndTokenMeasurements() async throws {
  let failure = TextGenerationFailure(
    reason: .outputTokenLimit,
    metrics: .init(
      tokens: .init(processedPrompt: 800, cachedPrompt: 0, generated: 240),
      timing: .init(prompt: 0.2, generation: 2)))
  let fixture = try TextStreamFixture(failure: failure)
  defer { fixture.remove() }
  let model = try await MLXTextModelProvider(executable: fixture.url).prepare(fixture.preparation)
  do {
    _ = try await model.stream(fixture.request, receive: { _ in })
    Issue.record("A token-limited native result must remain a failure")
  } catch let received as TextGenerationFailure {
    #expect(received.reason == .outputTokenLimit)
    #expect(received.metrics?.generatedTokens == 240)
    #expect(received.metrics?.processedPromptTokens == 800)
    #expect(received.localizedDescription == TextModelError.invalidResponse.localizedDescription)
  }
  await model.stop()
}
