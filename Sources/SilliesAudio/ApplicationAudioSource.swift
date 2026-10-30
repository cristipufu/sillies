import CoreMedia
import Foundation
import ScreenCaptureKit
import SilliesCore
import Synchronization

/// ScreenCaptureKit taps the selected application's audio; it never redirects or plays it.
final class ApplicationAudioSource: NSObject, SCStreamOutput, SCStreamDelegate, Sendable {
  private static let sampleRate = 48_000
  private static let channelCount = 1
  private static let unusedVideoDimension = 2
  private let target: WindowTargetCandidate
  private let receive: AudioCaptureInputQueue.Receiver
  private let failure: @Sendable (String) -> Void
  private let queue = DispatchQueue(label: "app.sillies.application-audio", qos: .userInitiated)
  // SCStream has no Sendable conformance. This slot is accessed only under the state Mutex;
  // start publishes it once, and stop removes it before awaiting SDK shutdown.
  private struct State: @unchecked Sendable {
    var stream: SCStream?
    var stopped = false
  }
  private let state = Mutex(State())

  init(
    target: WindowTargetCandidate, receive: @escaping AudioCaptureInputQueue.Receiver,
    failure: @escaping @Sendable (String) -> Void
  ) {
    self.target = target
    self.receive = receive
    self.failure = failure
  }

  func start() async throws {
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: false)
    guard let display = content.displays.first,
      let application = content.applications.first(where: { $0.processID == target.processID })
    else {
      throw AudioCaptureFailure.unavailable("The selected application is no longer available.")
    }
    guard !state.withLock({ $0.stopped }) else { throw CancellationError() }
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
    try await stream.startCapture()
    let cancelled = state.withLock { state in
      guard !state.stopped else { return true }
      state.stream = stream
      return false
    }
    if cancelled {
      try await stream.stopCapture()
      throw CancellationError()
    }
  }

  func stop(completion: @escaping @Sendable () -> Void = {}) {
    let active = state.withLock { state in
      state.stopped = true
      let active = state.stream
      state.stream = nil
      return active
    }
    guard let active else {
      completion()
      return
    }
    Task.detached {
      do { try await active.stopCapture() } catch {
        fputs("Application audio stop failed: \(error.localizedDescription)\n", stderr)
      }
      completion()
    }
  }

  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of outputType: SCStreamOutputType
  ) {
    if outputType == .audio, sampleBuffer.isValid,
      let packet = AudioCaptureInputQueue.Packet(sample: sampleBuffer, source: .application)
    {
      receive(packet)
    }
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    guard !state.withLock({ $0.stopped }) else { return }
    failure("Application audio stopped: \(error.localizedDescription)")
  }
}
