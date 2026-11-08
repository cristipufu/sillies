import Foundation
import SilliesCore
import SilliesInference
import SilliesModelStore
import SilliesSpeech
import SilliesSpeechParakeet
import Synchronization
import Testing

@testable import SilliesApp
@testable import SilliesAudio

/// Uses verified local weights and the production warmup chain, never a real microphone.
@Test(
  .enabled(if: ProcessInfo.processInfo.environment["SILLIES_CONVERSATION_STARTUP_CHECK"] == "1"))
func downloadedConversationStartupReachesListeningAndReleasesAdmission() async throws {
  let path = try #require(ProcessInfo.processInfo.environment["SILLIES_STT_STORE"])
  let store = ModelStore(root: URL(fileURLWithPath: path))
  let registry = try SpeechRuntimeRegistry(store: store, providers: [ParakeetSpeechProvider()])
  let model = try await registry.currentManifest("parakeet-ultra").model
  let cache = DictationRuntimeCache(registry: registry)
  let activity = InferenceActivity()
  let microphone = StartupMicrophone()
  let listening = Mutex(false)
  let failure = Mutex<SessionFailure?>(nil)
  var configuration = AudioCaptureConfiguration(
    kind: .chat, target: nil, recordingURL: nil, language: .automatic)
  configuration.model = model
  let capture = VoiceConversationCapture(
    configuration: configuration, reference: VoicePlaybackReference(),
    resources: .init(
      audio: .init(
        microphone: { _, _ in microphone },
        speech: { _, _, _ in
          Issue.record("Initial silence must not create a recognizer turn")
          throw CancellationError()
        }),
      warmSpeech: {
        try await activity.prepareSpeechRuntime { try await cache.prepare(model: model) }
      }),
    update: { update in
      switch update {
      case .capturing: listening.withLock { $0 = true }
      case .failed(let error): failure.withLock { $0 = error }
      default: break
      }
    })
  let started = ContinuousClock.now
  capture.start()
  let deadline = started.advanced(by: .seconds(50))
  while !listening.withLock({ $0 }), failure.withLock({ $0 == nil }),
    ContinuousClock.now < deadline
  {
    try await Task.sleep(for: .milliseconds(10))
  }
  print("Conversation startup: \(started.duration(to: .now))")
  let result: AudioCaptureResult = await withCheckedContinuation { continuation in
    capture.finish { continuation.resume(returning: $0) }
  }
  await cache.stop()
  #expect(listening.withLock { $0 })
  #expect(failure.withLock { $0 } == nil)
  #expect(result.failure == nil)
  #expect(microphone.starts.withLock { $0 } == 1)
  #expect(microphone.stops.withLock { $0 } == 1)
  let text = UUID()
  #expect(await activity.claimText(text, cancel: {}))
  await activity.releaseText(text)
}

private final class StartupMicrophone: MicrophoneCapture {
  let starts = Mutex(0)
  let stops = Mutex(0)
  func start() async throws -> String {
    starts.withLock { $0 += 1 }
    return "Headless microphone fixture"
  }
  func stop(completion: @escaping @Sendable () -> Void) {
    stops.withLock { $0 += 1 }
    completion()
  }
}
