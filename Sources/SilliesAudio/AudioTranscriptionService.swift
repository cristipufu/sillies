import AVFoundation
import CoreMedia
import Foundation
import SilliesCore
import Synchronization

/// Owns one session, with bounded input and UI publication. All DSP, speech, and file work is off-main.
package final class AudioTranscriptionService: SessionAudioCapture, @unchecked Sendable {
  private static let publicationInterval: TimeInterval = 0.5
  private static let finishTimeout: TimeInterval = 8
  private let configuration: AudioCaptureConfiguration
  private let onUpdate: @Sendable (AudioCaptureUpdate) -> Void
  private let queue: DispatchQueue
  private let inputQueue: AudioCaptureInputQueue
  private struct Lifecycle {
    var stopped = false
    var startup: Task<Void, Never>?
  }
  private let lifecycle = Mutex(Lifecycle())
  // The following state is confined to queue.
  private var speech: SessionSpeechPipeline?
  private var microphone: MicrophoneAudioSource?
  private var application: ApplicationAudioSource?
  private var writer: AudioRecordingWriter?
  private var meetingAudio: MeetingAudioProcessor?
  private var paused = false
  private var capturing = false
  private var startedAt: TimeInterval = 0
  private var pausedAt: TimeInterval?
  private var pausedDuration: TimeInterval = 0
  private var lastPublishedAt: TimeInterval = 0
  private var failure: String?
  private var finishDelivered = false
  private var pendingStops = 0

  package init(
    configuration: AudioCaptureConfiguration,
    onUpdate: @escaping @Sendable (AudioCaptureUpdate) -> Void
  ) {
    let queue = DispatchQueue(label: "app.sillies.audio-session", qos: .utility)
    self.queue = queue
    inputQueue = AudioCaptureInputQueue(queue: queue)
    self.configuration = configuration
    self.onUpdate = onUpdate
  }

  package func start() {
    let task = Task.detached(priority: .utility) { [self] in
      do {
        onUpdate(.preparing("Preparing on-device speech…"))
        try Task.checkCancellation()
        try await beginCapture()
      } catch is CancellationError {
        // Finishing during permission/model preparation is a normal cancellation.
      } catch { reportFailure(error.localizedDescription) }
    }
    lifecycle.withLock {
      $0.startup = task
      if $0.stopped { task.cancel() }
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
      guard !lifecycle.withLock({ $0.stopped }), failure == nil else { return }
      startedAt = AudioCaptureClock.now
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
        guard !lifecycle.withLock({ $0.stopped }) else {
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
    dispatchPrecondition(condition: .onQueue(queue))
    switch event {
    case .textChanged: if !finishDelivered { publish(level: 0) }
    case .changingLanguage(let language): onUpdate(.changingLanguage(language))
    case .languageChanged(let language): onUpdate(.languageChanged(language))
    case .failed(let message): fail(message)
    }
  }

  package func changeLanguage(_ language: SpeechLanguage) {
    queue.async { [self] in
      guard capturing, !lifecycle.withLock({ $0.stopped }) else { return }
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
          guard !lifecycle.withLock({ $0.stopped }) else { throw CancellationError() }
          if let url = configuration.recordingURL {
            writer = try AudioRecordingWriter(destination: url)
          }
          if configuration.kind.isMeetingSession {
            meetingAudio = try MeetingAudioProcessor()
          }
          if configuration.sources.contains(.microphone) {
            microphone = MicrophoneAudioSource(
              receive: { [weak self] in self?.enqueue($0) },
              failure: { [weak self] in self?.reportFailure($0) })
          }
          if configuration.sources.contains(.application) {
            guard let target = configuration.target else {
              throw AudioCaptureFailure.unavailable("Choose a meeting window first.")
            }
            application = ApplicationAudioSource(
              target: target,
              receive: { [weak self] in self?.enqueue($0) },
              failure: { [weak self] in self?.reportFailure($0) })
          }
          continuation.resume(
            returning: CaptureSources(application: application, microphone: microphone))
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  package func pause() {
    queue.async { [self] in
      guard capturing, !paused else { return }
      do {
        try flushMeetingAudio()
        try meetingAudio?.reset()
      } catch {
        fail(error.localizedDescription)
        return
      }
      paused = true
      pausedAt = AudioCaptureClock.now
    }
  }

  package func resume() {
    queue.async { [self] in
      guard capturing, paused else { return }
      if let pausedAt { pausedDuration += AudioCaptureClock.now - pausedAt }
      pausedAt = nil
      paused = false
    }
  }

  package func refreshProgress() {
    queue.async { [self] in
      guard capturing, !lifecycle.withLock({ $0.stopped }) else { return }
      publish(level: 0)
    }
  }

  private func enqueue(_ packet: AudioCaptureInputQueue.Packet) {
    inputQueue.enqueue(
      packet, receive: { [weak self] in self?.process($0) },
      overflow: { [weak self] in
        self?.fail(
          "Audio capture fell behind. Finish to save the available transcript and recording.")
      })
  }

  private func process(_ packet: AudioCaptureInputQueue.Packet) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard capturing, !paused, failure == nil,
      let buffer = AudioPCMTools.buffer(from: packet.sample)
    else { return }
    do {
      if let meetingAudio {
        try meetingAudio.append(buffer, source: packet.source, at: packet.sampleStartTime)
        while let output = try meetingAudio.nextReadyOutput() { try consume(output) }
      } else {
        try writer?.append(buffer)
        speech?.append(
          buffer, source: packet.source,
          elapsed: max(0, packet.capturedAt - startedAt - pausedDuration))
      }
      publish(level: AudioPCMTools.level(buffer))
    } catch { fail(error.localizedDescription) }
  }

  private func consume(_ output: MeetingAudioProcessor.Output) throws {
    let elapsed = max(0, output.endTime - startedAt - pausedDuration)
    try writer?.append(output.recording)
    speech?.append(output.meeting, source: .application, elapsed: elapsed)
    speech?.append(output.microphone, source: .microphone, elapsed: elapsed)
  }

  private func flushMeetingAudio() throws {
    while let output = try meetingAudio?.nextFinalOutput() { try consume(output) }
  }

  private var elapsed: TimeInterval {
    guard startedAt > 0 else { return 0 }
    return max(0, (pausedAt ?? AudioCaptureClock.now) - startedAt - pausedDuration)
  }

  private var transcript: String {
    speech?.text ?? ""
  }

  private func publish(level: Double) {
    dispatchPrecondition(condition: .onQueue(queue))
    let now = AudioCaptureClock.now
    guard now - lastPublishedAt >= Self.publicationInterval else { return }
    lastPublishedAt = now
    onUpdate(
      .transcript(
        speech?.preview ?? "", level: level, elapsed: elapsed))
  }

  private func reportFailure(_ message: String) { queue.async { [self] in fail(message) } }

  private func fail(_ message: String) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard failure == nil, !lifecycle.withLock({ $0.stopped }) else { return }
    failure = message
    inputQueue.stop()
    capturing = false
    if startedAt > 0 { pausedAt = AudioCaptureClock.now }
    microphone?.stop()
    application?.stop()
    speech?.cancel()
    meetingAudio = nil
    onUpdate(.failed(message))
    fputs("Audio session failed: \(message)\n", stderr)
  }

  package func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    inputQueue.stop()
    lifecycle.withLock {
      $0.stopped = true
      $0.startup?.cancel()
    }
    queue.async { [self] in
      do { try flushMeetingAudio() } catch {
        failure = failure ?? error.localizedDescription
        fputs("Meeting audio finalization failed: \(error.localizedDescription)\n", stderr)
      }
      meetingAudio = nil
      capturing = false
      if pausedAt == nil { pausedAt = AudioCaptureClock.now }
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
      queue.asyncAfter(deadline: .now() + Self.finishTimeout) { [weak self] in
        guard let self, !self.finishDelivered else { return }
        self.speech?.cancel()
        self.failure =
          self.failure ?? "Saved the available transcript; speech finalization timed out."
        self.deliverFinish(completion)
      }
    }
  }

  private func deliverFinish(_ completion: @Sendable (AudioCaptureResult) -> Void) {
    dispatchPrecondition(condition: .onQueue(queue))
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
