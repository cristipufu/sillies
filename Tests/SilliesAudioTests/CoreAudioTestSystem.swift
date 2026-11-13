import CoreAudio
import Foundation
import SilliesCore
import Synchronization

@testable import SilliesAudio

/// A thread-safe HAL fixture: callbacks can race the capture worker without native devices.
final class CoreAudioTestSystem: CoreAudioTapSystem, Sendable {
  enum Step: String, CaseIterable, Sendable {
    case selection, tap, device, format, processor, observe, start
    case removeObservers, stop, destroyProcessor, destroyDevice, destroyTap
  }
  struct State {
    var steps: [Step] = []
    var failures: [Step: Int] = [:]
    var selection = CoreAudioTapSelection(
      processes: [21], output: .init(id: 31, uid: "fixture-output", sampleRate: 48_000))
    var changed: (@Sendable (CoreAudioCaptureChange) -> Void)?
    var receive: CoreAudioInputCallback?
    var oldReceivers: [CoreAudioInputCallback] = []
    var hooks: [Step: @Sendable () -> Void] = [:]
    var status = kAudioHardwareUnspecifiedError
    var statuses: [Step: OSStatus] = [:]
  }
  let state = Mutex(State())
  static let target = WindowTargetCandidate(
    windowID: 7, processID: 42, appName: "Fixture", bundleIdentifier: "test.fixture", frame: .zero)
  static var format: AudioStreamBasicDescription {
    .init(
      mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
      mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
      mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
  }
  private func perform(_ step: Step) throws {
    let (hook, status) = state.withLock { state -> ((@Sendable () -> Void)?, OSStatus?) in
      state.steps.append(step)
      let remaining = state.failures[step, default: 0]
      if remaining > 0 { state.failures[step] = remaining - 1 }
      return (state.hooks[step], remaining > 0 ? state.statuses[step] ?? state.status : nil)
    }
    hook?()
    if let status { throw CoreAudioCaptureError.native(.start, status) }
  }
  func selection(for target: WindowTargetCandidate) throws -> CoreAudioTapSelection {
    try perform(.selection)
    return state.withLock { $0.selection }
  }
  func createTap(processes: [AudioObjectID]) throws -> CoreAudioTapHandle {
    try perform(.tap)
    return .init(id: 51, uid: "fixture-tap")
  }
  func createDevice(tap: CoreAudioTapHandle, output: CoreAudioTapSelection.Output) throws
    -> AudioObjectID
  {
    try perform(.device)
    return 61
  }
  func inputFormat(device: AudioObjectID) throws -> AudioStreamBasicDescription {
    try perform(.format)
    return Self.format
  }
  func createProcessor(device: AudioObjectID, receive: @escaping CoreAudioInputCallback) throws
    -> UUID
  {
    try perform(.processor)
    state.withLock {
      $0.receive = receive
      $0.oldReceivers.append(receive)
    }
    return UUID()
  }
  func observe(
    _ objects: CoreAudioObservedObjects,
    changed: @escaping @Sendable (CoreAudioCaptureChange) -> Void
  ) throws {
    state.withLock { $0.changed = changed }
    try perform(.observe)
  }
  func start(device: AudioObjectID, processor: UUID) throws { try perform(.start) }
  func stop(device: AudioObjectID, processor: UUID) throws { try perform(.stop) }
  func removeObservers() throws {
    try perform(.removeObservers)
    state.withLock { $0.changed = nil }
  }
  func destroyProcessor(device: AudioObjectID, processor: UUID) throws {
    try perform(.destroyProcessor)
    state.withLock { $0.receive = nil }
  }
  func destroyDevice(_ device: AudioObjectID) throws { try perform(.destroyDevice) }
  func destroyTap(_ tap: AudioObjectID) throws { try perform(.destroyTap) }
  func change(_ change: CoreAudioCaptureChange) { state.withLock { $0.changed }?(change) }
}

func coreAudioStop(_ capture: any ApplicationCapture) async -> SessionFailure? {
  await withCheckedContinuation { continuation in
    capture.stop { continuation.resume(returning: $0) }
  }
}

func coreAudioSend(_ callback: CoreAudioInputCallback, values: [Float] = [0.25, -0.5]) {
  var samples = values
  samples.withUnsafeMutableBytes { bytes in
    var list = AudioBufferList(
      mNumberBuffers: 1,
      mBuffers: AudioBuffer(
        mNumberChannels: 1, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
    withUnsafePointer(to: &list) { callback($0, AudioTimeStamp()) }
    // HAL storage can be reused immediately after its borrowed callback returns.
    _ = bytes.initializeMemory(as: UInt8.self, repeating: 0)
  }
}
