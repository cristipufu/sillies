import Foundation
import SilliesInference
import SilliesSpeech
import Synchronization
import Testing

@testable import SilliesModelStore
@testable import SilliesSpeechActivity

@Test func activityValidationUsesAdmissionAndFreshRequestsWithoutConcurrentPredictions()
  async throws
{
  let backend = ControlledActivityValidator()
  let model = SpeechActivityModel(validator: backend, activity: InferenceActivity())
  let first = Task { try await model.containsSpeech([0.1]) }
  await backend.waitForFirst()
  let second = Task { try await model.containsSpeech([0.2]) }
  await backend.releaseFirst()
  #expect(try await first.value)
  #expect(try await second.value)
  #expect(await backend.maximumConcurrent == 1)
  #expect(await backend.inputs == [[0.1], [0.2]])
}

@Test func cancelledActivityValidationStopsBetweenPredictionsAndAllowsReuse() async throws {
  let backend = ControlledActivityValidator()
  let model = SpeechActivityModel(validator: backend, activity: InferenceActivity())
  let first = Task { try await model.containsSpeech([0.1]) }
  await backend.waitForFirst()
  first.cancel()
  await backend.releaseFirst()
  await #expect(throws: CancellationError.self) { try await first.value }
  #expect(try await model.containsSpeech([0.3]))
  #expect(await backend.maximumConcurrent == 1)
}

@Test func nativeActivityInputFailuresAreRecoverableWithoutLoadingOrDownloadingModels() async throws
{
  let engine = NativeSpeechActivityEngine()
  for samples: [Float] in [[.nan], [.infinity], [Float](repeating: 0, count: 192_001)] {
    await #expect(throws: SpeechError.self) { try await engine.containsSpeech(samples) }
  }
  #expect(try await !engine.containsSpeech([]))
  await #expect(throws: SpeechError.self) { try await engine.containsSpeech([0.1]) }
  await #expect(throws: (any Error).self) {
    try await engine.load(URL(fileURLWithPath: "/nonexistent/sillies-public-vad-test.mlmodelc"))
  }
}

@Test func cancelledNativeActivityPreparationStopsBeforeModelIO() async {
  let engine = NativeSpeechActivityEngine()
  let work = Task {
    withUnsafeCurrentTask { $0?.cancel() }
    try await engine.load(URL(fileURLWithPath: "/nonexistent/sillies-cancelled-vad.mlmodelc"))
  }
  await #expect(throws: CancellationError.self) { try await work.value }
}

@Test func nativeActivityOwnerRetainsItsInstallationUntilWorkerDestruction() async throws {
  let released = Mutex(0)
  let (events, signal) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  var lease: InstalledModelLease? = InstalledModelLease(
    directory: URL(fileURLWithPath: "/unused/sillies-model-lifetime-test"), token: UUID(),
    release: {
      released.withLock { $0 += 1 }
      signal.yield(())
      signal.finish()
    })
  var engine: NativeSpeechActivityEngine? = NativeSpeechActivityEngine(lease: try #require(lease))
  lease = nil
  #expect(try await engine?.containsSpeech([]) == false)
  withExtendedLifetime(engine) { #expect(released.withLock { $0 } == 0) }
  engine = nil
  for await _ in events {}
  #expect(released.withLock { $0 } == 1)
}

private actor ControlledActivityValidator: SpeechWindowValidating {
  private var started: CheckedContinuation<Void, Never>?
  private var release: CheckedContinuation<Void, Never>?
  private var isFirstRunning = false
  private var concurrent = 0
  private(set) var maximumConcurrent = 0
  private(set) var inputs: [[Float]] = []

  func containsSpeech(_ samples: [Float]) async throws -> Bool {
    concurrent += 1
    maximumConcurrent = max(maximumConcurrent, concurrent)
    inputs.append(samples)
    defer { concurrent -= 1 }
    if inputs.count == 1 {
      isFirstRunning = true
      started?.resume()
      started = nil
      await withCheckedContinuation { release = $0 }
    }
    try Task.checkCancellation()
    return true
  }
  func waitForFirst() async {
    guard !isFirstRunning else { return }
    await withCheckedContinuation { started = $0 }
  }
  func releaseFirst() {
    release?.resume()
    release = nil
  }
}
