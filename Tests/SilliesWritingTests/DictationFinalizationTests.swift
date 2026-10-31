import Foundation
import SilliesAudio
import SilliesCore
import SilliesSpeech
import SilliesWriting
import Synchronization
import Testing

private final class DeferredWritingCapture: SessionAudioCapture {
  private let callback = Mutex<(@Sendable (AudioCaptureResult) -> Void)?>(nil)
  let update: @Sendable (AudioCaptureUpdate) -> Void
  init(update: @escaping @Sendable (AudioCaptureUpdate) -> Void) { self.update = update }
  func start() { update(.capturing("Microphone")) }
  func pause() {}
  func resume() {}
  func changeLanguage(_ language: SpeechLanguage) {}
  func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    callback.withLock { $0 = completion }
  }
  func completeTwice() {
    var result = AudioCaptureResult(
      transcript: "Recover me", recordingURL: nil, duration: 2, failure: nil)
    result.segments = [.init(sequence: 0, source: "You", start: 0, end: 2, text: "Recover me")]
    let completion = callback.withLock { $0 }
    completion?(result)
    completion?(result)
  }
}
private enum StopIntent: CaseIterable, Sendable { case cancel, suspend }
@Test(arguments: StopIntent.allCases) @MainActor
private func dictationFinalizationDrainsOnceAndRespectsExplicitCancellation(_ intent: StopIntent)
  async throws
{
  let captures = Mutex<DeferredWritingCapture?>(nil)
  let history = RecoveryHistory()
  let destination = WritingDestination()
  let session = testDictation(
    insertion: destination, history: history,
    configuration: .init(factory: { _, update in
      let capture = DeferredWritingCapture(update: update)
      captures.withLock { $0 = capture }
      return capture
    }))
  session.start(.toggle)
  try await eventually { session.canFinish }
  session.finish()
  switch intent {
  case .cancel: session.cancel()
  case .suspend: session.suspend()
  }
  var flushes = 0
  session.flushForTermination { flushes += 1 }
  #expect(session.isBusy)
  let capture = try #require(captures.withLock { $0 })
  capture.completeTwice()
  try await eventually { flushes > 0 }
  #expect(flushes == 1)
  #expect(!session.isBusy)
  #expect(await destination.inserted.isEmpty)
  #expect(history.flushed)
  switch intent {
  case .cancel: #expect(history.results.isEmpty)
  case .suspend: #expect(history.results.map(\.text) == ["Recover me"])
  }
}

private actor DelayedInsertion: TextInserting {
  private var pending: CheckedContinuation<Void, Never>?
  var isWaiting: Bool { pending != nil }
  private var count = 0
  func capture(_ application: FrontmostApplication) -> TextDestination {
    .init(id: UUID(), application: application, selection: "")
  }
  func insert(_ text: String, into destination: TextDestination) async {
    count += 1
    if count == 1 { await withCheckedContinuation { pending = $0 } }
  }
  func finishFirst() {
    pending?.resume()
    pending = nil
  }
  func release(_ destination: TextDestination) {}
}
@Test @MainActor func dictationLateInsertionCannotPublishResultOrLatencyIntoTheNextRun()
  async throws
{
  let destination = DelayedInsertion()
  let history = RecoveryHistory()
  let session = testDictation(insertion: destination, history: history)
  session.start(.toggle)
  try await eventually { session.canFinish }
  session.finish()
  for _ in 0..<200 {
    if await destination.isWaiting { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  try #require(await destination.isWaiting)
  session.cancel()
  session.start(.toggle)
  await destination.finishFirst()
  try await eventually { session.canFinish && history.results.first?.delivery == .inserted }
  #expect(session.result == nil)
  #expect(session.releaseToInsertion == nil)
  #expect(session.insertionFailure == nil)
  session.finish()
  try await eventually { session.result != nil }
  #expect(history.results.count == 2)
  #expect(session.result?.delivery == .inserted)
  session.dismiss()
}

@Test @MainActor func dictationUsesTheOutputStyleChosenAtSessionStart() async throws {
  let preferences = WritingPreferences()
  let transforms = Mutex(0)
  let session = testDictation(
    insertion: WritingDestination(), history: RecoveryHistory(),
    configuration: .init(
      preferences: preferences,
      transform: { text, _ in
        transforms.withLock { $0 += 1 }
        return text
      }))
  session.start(.toggle)
  try await eventually { session.canFinish }
  preferences.style = .lightlyCleaned
  session.finish()
  try await eventually { session.result != nil }
  #expect(transforms.withLock { $0 } == 0)
  #expect(session.result?.delivery == .inserted)
  session.dismiss()
}

private final class HeldWritingDelivery: Sendable {
  private let callbacks = Mutex<[@MainActor @Sendable () -> Void]>([])
  var hasPending: Bool { callbacks.withLock { !$0.isEmpty } }
  func enqueue(_ callback: @escaping @MainActor @Sendable () -> Void) {
    callbacks.withLock { $0.append(callback) }
  }
  @MainActor func drain() {
    let pending = callbacks.withLock { value in
      defer { value.removeAll() }
      return value
    }
    for callback in pending { callback() }
  }
}
@Test @MainActor func dictationQuitPreservesFinalizedAudioBeforeItsDeliveryTaskCanRun() async throws
{
  let delivery = HeldWritingDelivery()
  let history = RecoveryHistory()
  let destination = WritingDestination()
  let session = testDictation(
    insertion: destination, history: history,
    configuration: .init(deliver: { delivery.enqueue($0) }))
  session.start(.toggle)
  try await eventually { delivery.hasPending }
  delivery.drain()
  try #require(session.canFinish)
  session.finish()
  delivery.drain()
  // Still on the same main-actor turn: delivery's Task cannot have started yet.
  var flushed = false
  session.flushForTermination { flushed = true }
  #expect(flushed)
  #expect(history.results.map(\.text) == ["Ștefan uses API_v2."])
  #expect(history.results.first?.delivery == .needsPaste)
  #expect(await destination.inserted.isEmpty)
  #expect(!session.isBusy)
}
