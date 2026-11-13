import CoreAudio
import Foundation
import SilliesCore

/// Resource operations execute only on the owning capture worker; no SDK handle escapes it.
protocol CoreAudioTapSystem: AnyObject {
  func selection(for target: WindowTargetCandidate) throws -> CoreAudioTapSelection
  func createTap(processes: [AudioObjectID]) throws -> CoreAudioTapHandle
  func createDevice(tap: CoreAudioTapHandle, output: CoreAudioTapSelection.Output) throws
    -> AudioObjectID
  func inputFormat(device: AudioObjectID) throws -> AudioStreamBasicDescription
  func createProcessor(device: AudioObjectID, receive: @escaping CoreAudioInputCallback) throws
    -> UUID
  func observe(
    _ objects: CoreAudioObservedObjects,
    changed: @escaping @Sendable (CoreAudioCaptureChange) -> Void) throws
  func start(device: AudioObjectID, processor: UUID) throws
  func stop(device: AudioObjectID, processor: UUID) throws
  func removeObservers() throws
  func destroyProcessor(device: AudioObjectID, processor: UUID) throws
  func destroyDevice(_ device: AudioObjectID) throws
  func destroyTap(_ tap: AudioObjectID) throws
}
typealias CoreAudioInputCallback =
  @Sendable (UnsafePointer<AudioBufferList>, AudioTimeStamp) -> Void
struct CoreAudioTapHandle: Sendable {
  let id: AudioObjectID
  let uid: String
}
struct CoreAudioTapSelection: Equatable, Sendable {
  struct Output: Equatable, Sendable {
    let id: AudioObjectID
    let uid: String
    let sampleRate: Double
  }
  let processes: [AudioObjectID]
  let output: Output
}
struct CoreAudioObservedObjects {
  let device: AudioObjectID
  let tap: AudioObjectID
  let output: AudioObjectID
}
enum CoreAudioCaptureChange: Sendable {
  case processes, configuration
}
