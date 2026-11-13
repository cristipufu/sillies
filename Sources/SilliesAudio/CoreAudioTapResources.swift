import CoreAudio
import Foundation

/// One worker owns the resource graph. A failed release keeps the handle for a later cleanup attempt.
final class CoreAudioTapResources {
  private static let cleanupAttempts = 2
  private let system: any CoreAudioTapSystem
  private(set) var tap: CoreAudioTapHandle?
  private(set) var device: AudioObjectID?
  private var processor: UUID?
  private var didAttemptStart = false
  init(system: any CoreAudioTapSystem) { self.system = system }

  func prepare(_ selection: CoreAudioTapSelection) throws -> AudioStreamBasicDescription {
    guard tap == nil, device == nil, processor == nil else {
      throw CoreAudioCaptureError.unsupported
    }
    let tap = try system.createTap(processes: selection.processes)
    self.tap = tap
    let device = try system.createDevice(tap: tap, output: selection.output)
    self.device = device
    return try system.inputFormat(device: device)
  }
  func start(
    receive: @escaping CoreAudioInputCallback,
    changed: @escaping @Sendable (CoreAudioCaptureChange) -> Void, output: AudioObjectID
  ) throws {
    guard let device, let tap, processor == nil else { throw CoreAudioCaptureError.unsupported }
    let processor = try system.createProcessor(device: device, receive: receive)
    self.processor = processor
    try system.observe(.init(device: device, tap: tap.id, output: output), changed: changed)
    didAttemptStart = true
    try system.start(device: device, processor: processor)
  }
  func release() -> CoreAudioCaptureError? {
    var failure: CoreAudioCaptureError?
    for _ in 0..<Self.cleanupAttempts {
      do {
        try releaseOwnedResources()
        return nil
      } catch {
        failure =
          (error as? CoreAudioCaptureError) ?? .native(.stop, kAudioHardwareUnspecifiedError)
      }
    }
    fputs("Core Audio resource cleanup failed.\n", stderr)
    return failure
  }
  private func releaseOwnedResources() throws {
    // Listener removal must never prevent stopping a running IOProc.
    var observerFailure: Error?
    do { try system.removeObservers() } catch { observerFailure = error }
    if let device, let processor {
      if didAttemptStart {
        try system.stop(device: device, processor: processor)
        didAttemptStart = false
      }
      try system.destroyProcessor(device: device, processor: processor)
      self.processor = nil
    }
    // Keep observed objects alive if listener removal still needs a retry.
    if let observerFailure { throw observerFailure }
    if let device {
      try system.destroyDevice(device)
      self.device = nil
    }
    if let tap {
      try system.destroyTap(tap.id)
      self.tap = nil
    }
  }
}
