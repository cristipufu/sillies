import AVFoundation
import CoreMedia
import Foundation
import SilliesCore

enum SessionAudioSource: String, CaseIterable, Sendable {
  case application = "Meeting"
  case microphone = "Microphone"
}

struct AudioCaptureConfiguration: Sendable {
  let kind: CompanionSkillKind
  let target: WindowTargetCandidate?
  let recordingURL: URL?
  var language: SpeechLanguage?
  var sources: [SessionAudioSource] {
    switch kind {
    case .participate: [.application, .microphone]
    case .record: [.microphone]
    default: [.application]
    }
  }
}

struct AudioCaptureResult: Sendable {
  let transcript: String
  let recordingURL: URL?
  let duration: TimeInterval
  let error: String?
}

/// Owns one session, with bounded input and UI publication. All DSP, speech, and file work is off-main.
final class AudioTranscriptionService: SessionAudioCapture, @unchecked Sendable {
  enum Update: Sendable {
    case preparing(String)
    case capturing(String)
    case changingLanguage(SpeechLanguage)
    case languageChanged(SpeechLanguage)
    case transcript(String, level: Double, elapsed: TimeInterval)
    case failed(String)
  }
  private static let publicationInterval: TimeInterval = 0.5
  private static let finishTimeout: TimeInterval = 8
  private let configuration: AudioCaptureConfiguration
  private let onUpdate: @Sendable (Update) -> Void
  private let queue: DispatchQueue
  private let inputQueue: AudioCaptureInputQueue
  private let lock = NSLock()
  private var stopped = false
  private var startup: Task<Void, Never>?
  // The following state is confined to queue.
  private var speech: SessionSpeechPipeline?
  private var microphone: MicrophoneAudioSource?
  private var application: ApplicationAudioSource?
  private var writer: AudioRecordingWriter?
  private var paused = false
  private var capturing = false
  private var startedAt: TimeInterval = 0
  private var pausedAt: TimeInterval?
  private var pausedDuration: TimeInterval = 0
  private var lastPublishedAt: TimeInterval = 0
  private var failure: String?
  private var finishDelivered = false
  private var pendingStops = 0

  init(configuration: AudioCaptureConfiguration, onUpdate: @escaping @Sendable (Update) -> Void) {
    let queue = DispatchQueue(label: "app.sillies.audio-session", qos: .utility)
    self.queue = queue
    inputQueue = AudioCaptureInputQueue(queue: queue)
    self.configuration = configuration
    self.onUpdate = onUpdate
  }

  func start() {
    let task = Task.detached(priority: .utility) { [self] in
      do {
        onUpdate(.preparing("Preparing on-device speech…"))
        try Task.checkCancellation()
        try await beginCapture()
      } catch is CancellationError {
        // Finishing during permission/model preparation is a normal cancellation.
      } catch { reportFailure(error.localizedDescription) }
    }
    lock.withLock {
      startup = task
      if stopped { task.cancel() }
    }
  }

  private func beginCapture() async throws {
    let sources = try await prepareSources()
    try await prepareSpeech()
    if let application = sources.application { try await application.start() }
    try Task.checkCancellation()
    var microphoneName: String?
    if let microphone = sources.microphone { microphoneName = try await microphone.start() }
    try Task.checkCancellation()
    let label = [configuration.target?.appName, microphoneName].compactMap { $0 }.joined(
      separator: " + ")
    queue.async { [self] in
      guard !lock.withLock({ stopped }), failure == nil else { return }
      startedAt = ProcessInfo.processInfo.systemUptime
      capturing = true
      onUpdate(.capturing(label))
    }
  }

  private func prepareSpeech() async throws {
    guard let language = configuration.language else {
      throw AudioCaptureFailure.unavailable("Choose a transcription language before starting.")
    }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async { [self] in
        guard !lock.withLock({ stopped }) else {
          continuation.resume(throwing: CancellationError())
          return
        }
        let pipeline = SessionSpeechPipeline(
          configuration: .init(sources: configuration.sources, queue: queue)
        ) { [weak self] event in
          self?.speechChanged(event)
        }
        speech = pipeline
        pipeline.start(language: language) { continuation.resume(with: $0) }
      }
    }
  }

  private func speechChanged(_ event: SessionSpeechPipeline.Event) {
    switch event {
    case .textChanged: if !finishDelivered { publish(level: 0) }
    case .changingLanguage(let language): onUpdate(.changingLanguage(language))
    case .languageChanged(let language): onUpdate(.languageChanged(language))
    case .failed(let message): fail(message)
    }
  }

  func changeLanguage(_ language: SpeechLanguage) {
    queue.async { [self] in
      guard capturing, !lock.withLock({ stopped }) else { return }
      speech?.changeLanguage(language, elapsed: elapsed)
    }
  }

  private struct CaptureSources: Sendable {
    let application: ApplicationAudioSource?
    let microphone: MicrophoneAudioSource?
  }

  private func prepareSources() async throws -> CaptureSources {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        do {
          guard !lock.withLock({ stopped }) else { throw CancellationError() }
          if let url = configuration.recordingURL {
            writer = try AudioRecordingWriter(destination: url)
          }
          if configuration.sources.contains(.microphone) {
            microphone = MicrophoneAudioSource(
              receive: { [weak self] in self?.enqueue($0, from: .microphone) },
              failure: { [weak self] in self?.reportFailure($0) })
          }
          if configuration.sources.contains(.application) {
            guard let target = configuration.target else {
              throw AudioCaptureFailure.unavailable("Choose a meeting window first.")
            }
            application = ApplicationAudioSource(
              target: target,
              receive: { [weak self] in self?.enqueue($0, from: .application) },
              failure: { [weak self] in self?.reportFailure($0) })
          }
          continuation.resume(
            returning: CaptureSources(application: application, microphone: microphone))
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  func pause() {
    queue.async { [self] in
      guard capturing, !paused else { return }
      paused = true
      pausedAt = ProcessInfo.processInfo.systemUptime
    }
  }

  func resume() {
    queue.async { [self] in
      guard capturing, paused else { return }
      if let pausedAt { pausedDuration += ProcessInfo.processInfo.systemUptime - pausedAt }
      pausedAt = nil
      paused = false
    }
  }

  func refreshProgress() {
    queue.async { [self] in
      guard capturing, !lock.withLock({ stopped }) else { return }
      publish(level: 0)
    }
  }

  private func enqueue(_ sample: CMSampleBuffer, from source: SessionAudioSource) {
    guard let packet = AudioCaptureInputQueue.Packet(sample: sample, source: source) else { return }
    inputQueue.enqueue(
      packet, receive: { [weak self] in self?.process($0) },
      overflow: { [weak self] in
        self?.fail(
          "Audio capture fell behind. Finish to save the available transcript and recording.")
      })
  }

  private func process(_ packet: AudioCaptureInputQueue.Packet) {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard capturing, !paused, failure == nil,
      let buffer = AudioPCMTools.buffer(from: packet.sample)
    else { return }
    do {
      if packet.source == .microphone { try writer?.append(buffer) }
      speech?.append(
        buffer, source: packet.source,
        elapsed: max(0, packet.capturedAt - startedAt - pausedDuration))
      publish(level: AudioPCMTools.level(buffer))
    } catch { fail(error.localizedDescription) }
  }

  private var elapsed: TimeInterval {
    guard startedAt > 0 else { return 0 }
    return max(0, (pausedAt ?? ProcessInfo.processInfo.systemUptime) - startedAt - pausedDuration)
  }

  private var transcript: String {
    speech?.text ?? ""
  }

  private func publish(level: Double) {
    let now = ProcessInfo.processInfo.systemUptime
    guard now - lastPublishedAt >= Self.publicationInterval else { return }
    lastPublishedAt = now
    onUpdate(
      .transcript(
        SpeechTranscript.preview(of: transcript), level: level, elapsed: elapsed))
  }

  private func reportFailure(_ message: String) { queue.async { [self] in fail(message) } }

  private func fail(_ message: String) {
    guard failure == nil, !lock.withLock({ stopped }) else { return }
    failure = message
    inputQueue.stop()
    capturing = false
    if startedAt > 0 { pausedAt = ProcessInfo.processInfo.systemUptime }
    microphone?.stop()
    application?.stop()
    speech?.cancel()
    onUpdate(.failed(message))
    fputs("Audio session failed: \(message)\n", stderr)
  }

  func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    inputQueue.stop()
    lock.withLock {
      stopped = true
      startup?.cancel()
    }
    queue.async { [self] in
      capturing = false
      if pausedAt == nil { pausedAt = ProcessInfo.processInfo.systemUptime }
      pendingStops =
        (speech == nil ? 0 : 1) + (microphone == nil ? 0 : 1) + (application == nil ? 0 : 1)
      let stopped: @Sendable () -> Void = { [self] in
        queue.async { [self] in
          pendingStops -= 1
          if pendingStops == 0 { deliverFinish(completion) }
        }
      }
      if pendingStops == 0 { deliverFinish(completion) }
      microphone?.stop(completion: stopped)
      application?.stop(completion: stopped)
      speech?.finish { [self] notice in
        failure = failure ?? notice
        stopped()
      }
      queue.asyncAfter(deadline: .now() + Self.finishTimeout) { [self] in
        guard !finishDelivered else { return }
        speech?.cancel()
        failure = failure ?? "Saved the available transcript; speech finalization timed out."
        deliverFinish(completion)
      }
    }
  }

  private func deliverFinish(_ completion: @Sendable (AudioCaptureResult) -> Void) {
    guard !finishDelivered else { return }
    finishDelivered = true
    var audioURL: URL?
    do { audioURL = try writer?.finish() } catch {
      failure = "Audio could not be saved: \(error.localizedDescription)"
      fputs("Audio file finalization failed: \(error.localizedDescription)\n", stderr)
    }
    writer = nil
    completion(
      AudioCaptureResult(
        transcript: transcript, recordingURL: audioURL, duration: elapsed, error: failure))
  }
}
