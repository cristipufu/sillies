import CoreMedia
import Foundation
import ScreenCaptureKit
import SilliesCore
import Synchronization

/// ScreenCaptureKit taps the selected application's audio; it never redirects or plays it.
final class ScreenCaptureKitApplicationCapture: NSObject, SCStreamOutput, SCStreamDelegate, Sendable
{
  private static let sampleRate = 48_000
  private static let channelCount = 1
  private static let unusedVideoDimension = 2
  private let target: WindowTargetCandidate
  private let receive: AudioCaptureInputQueue.Receiver
  private let failure: @Sendable (SessionFailure) -> Void
  private let queue = DispatchQueue(label: "app.sillies.application-audio", qos: .userInitiated)
  // SCStream has no Sendable conformance. Native ownership transitions under this Mutex;
  // only the transition that takes ownership may await SDK shutdown.
  struct State: @unchecked Sendable {
    enum Phase {
      case idle, starting, stoppingStartup, stopping
      case active(SCStream)
      case stopped(SessionFailure?)
    }
    enum StopAction {
      case wait, finish
      case shutdown(SCStream)
      case completed(SessionFailure?)
    }
    var phase = Phase.idle
    var completions: [@Sendable (SessionFailure?) -> Void] = []
    var isEnding: Bool {
      switch phase {
      case .stoppingStartup, .stopping, .stopped: true
      case .idle, .starting, .active: false
      }
    }
    mutating func beginStartup() -> Bool {
      guard case .idle = phase else { return false }
      phase = .starting
      return true
    }
    mutating func publish(_ stream: SCStream) -> Bool {
      guard case .starting = phase else { return false }
      phase = .active(stream)
      return true
    }
    mutating func requestStop(_ completion: @escaping @Sendable (SessionFailure?) -> Void)
      -> StopAction
    {
      if case .stopped(let outcome) = phase { return .completed(outcome) }
      completions.append(completion)
      switch phase {
      case .starting:
        phase = .stoppingStartup
        return .wait
      case .stoppingStartup, .stopping: return .wait
      case .active(let stream):
        phase = .stopping
        return .shutdown(stream)
      case .idle:
        phase = .stopping
        return .finish
      case .stopped: return .wait
      }
    }
    mutating func finish(_ outcome: SessionFailure?) -> [@Sendable (SessionFailure?) -> Void] {
      if case .stopped = phase { return [] }
      phase = .stopped(outcome)
      let pending = completions
      completions.removeAll()
      return pending
    }
  }
  private let state = Mutex(State())

  init(
    target: WindowTargetCandidate, receive: @escaping AudioCaptureInputQueue.Receiver,
    failure: @escaping @Sendable (SessionFailure) -> Void
  ) {
    self.target = target
    self.receive = receive
    self.failure = failure
  }

  func start() async throws {
    let accepted = state.withLock { $0.beginStartup() }
    guard accepted else { throw CancellationError() }
    try await withTaskCancellationHandler {
      do { try await startCapture() } catch {
        finishStop(nil)
        if error is CancellationError { throw error }
        if let failure = error as? SessionFailure { throw failure }
        throw Self.captureFailure(error)
      }
    } onCancel: {
      self.stop { _ in }
    }
  }

  static func captureFailure(_ error: Error) -> SessionFailure {
    let native = error as NSError
    if native.domain == SCStreamErrorDomain,
      native.code == SCStreamError.Code.userDeclined.rawValue
    {
      return .permissionDenied(.openScreenRecordingSettings)
    }
    return SessionFailure(error, category: .captureUnavailable)
  }

  private func startCapture() async throws {
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: false)
    guard let display = content.displays.first,
      let application = content.applications.first(where: { $0.processID == target.processID })
    else {
      throw AudioCaptureFailure.unavailable(
        String(localized: "The selected application is no longer available."))
    }
    guard !state.withLock({ $0.isEnding }) else { throw CancellationError() }
    let filter = SCContentFilter(display: display, including: [application], exceptingWindows: [])
    let configuration = SCStreamConfiguration()
    configuration.capturesAudio = true
    configuration.excludesCurrentProcessAudio = true
    configuration.sampleRate = Self.sampleRate
    configuration.channelCount = Self.channelCount
    configuration.width = Self.unusedVideoDimension
    configuration.height = Self.unusedVideoDimension
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
    let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
    try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
    do { try await stream.startCapture() } catch {
      let cleanup = await shutdown(stream)
      finishStop(cleanup)
      // Startup keeps its native error identity; stop subscribers receive cleanup failures.
      throw error
    }
    let published = state.withLock { $0.publish(stream) }
    if !published {
      finishStop(await shutdown(stream))
      throw CancellationError()
    }
  }

  func stop(completion: @escaping @Sendable (SessionFailure?) -> Void) {
    let action = state.withLock { $0.requestStop(completion) }
    switch action {
    case .wait: break
    case .completed(let outcome): completion(outcome)
    case .finish: finishStop(nil)
    case .shutdown(let stream): Task.detached { [self] in finishStop(await shutdown(stream)) }
    }
  }

  private func shutdown(_ stream: SCStream) async -> SessionFailure? {
    do {
      try await stream.stopCapture()
      return nil
    } catch {
      fputs("Application audio stop failed.\n", stderr)
      return SessionFailure(error, category: .finalization)
    }
  }
  private func finishStop(_ outcome: SessionFailure?) {
    let completions = state.withLock { $0.finish(outcome) }
    for completion in completions { completion(outcome) }
  }

  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of outputType: SCStreamOutputType
  ) {
    if !state.withLock({ $0.isEnding }), outputType == .audio, sampleBuffer.isValid,
      let packet = AudioCaptureInputQueue.Packet(sample: sampleBuffer, source: .application)
    {
      receive(packet)
    }
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    guard !state.withLock({ $0.isEnding }) else { return }
    let mapped = Self.captureFailure(error)
    failure(
      mapped.recovery != nil
        ? mapped
        : SessionFailure(
          category: .captureInterrupted,
          message: String(localized: "Application audio stopped: \(error.localizedDescription)")))
  }
}
