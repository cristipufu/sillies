import CoreAudio
import Foundation
import SilliesCore

/// The capture worker owns every mutable HAL handle and listener in this adapter.
final class NativeCoreAudioTapSystem: CoreAudioTapSystem {
  private struct Observer {
    let object: AudioObjectID
    let address: AudioObjectPropertyAddress
    let block: AudioObjectPropertyListenerBlock
  }
  private static let maximumBundleIdentifierBytes = 1_024
  private let callbackQueue = DispatchQueue(
    label: "app.sillies.core-audio-samples", qos: .userInitiated)
  private let propertyQueue = DispatchQueue(
    label: "app.sillies.core-audio-properties", qos: .userInitiated)
  private var processors: [UUID: AudioDeviceIOProcID] = [:]
  private var observers: [Observer] = []
  private var inputStreams: [AudioObjectID: AudioObjectID] = [:]

  func selection(for target: WindowTargetCandidate) throws -> CoreAudioTapSelection {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard target.processID > 0, target.processID != ProcessInfo.processInfo.processIdentifier,
      let bundle = target.bundleIdentifier, !bundle.isEmpty,
      bundle.utf8.count <= Self.maximumBundleIdentifierBytes
    else { throw CoreAudioCaptureError.unsupported }
    return try .init(processes: selectedProcesses(bundle: bundle), output: defaultOutput())
  }
  private func selectedProcesses(bundle: String) throws -> [AudioObjectID] {
    let objects = try CoreAudioProperties.objects(
      .init(
        object: AudioObjectID(kAudioObjectSystemObject),
        selector: kAudioHardwarePropertyProcessObjectList))
    var selected: Set<AudioObjectID> = []
    for object in objects {
      guard object != kAudioObjectUnknown else { throw CoreAudioCaptureError.unsupported }
      do {
        let owner = try CoreAudioProperties.string(
          .init(object: object, selector: kAudioProcessPropertyBundleID))
        guard owner == bundle else { continue }
        let pid = Int32(
          bitPattern: try CoreAudioProperties.integer(
            .init(object: object, selector: kAudioProcessPropertyPID)))
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else {
          throw CoreAudioCaptureError.unsupported
        }
        selected.insert(object)
      } catch CoreAudioCaptureError.native(_, let status)
        where status == kAudioHardwareBadObjectError
      {
        // An unrelated client can disappear between the bounded inventory and its property read.
        continue
      }
    }
    guard !selected.isEmpty else { throw CoreAudioCaptureError.unsupported }
    return selected.sorted()
  }
  private func defaultOutput() throws -> CoreAudioTapSelection.Output {
    let output = try CoreAudioProperties.integer(
      .init(
        object: AudioObjectID(kAudioObjectSystemObject),
        selector: kAudioHardwarePropertyDefaultOutputDevice))
    guard output != kAudioObjectUnknown else { throw CoreAudioCaptureError.unsupported }
    let uid = try CoreAudioProperties.string(
      .init(object: output, selector: kAudioDevicePropertyDeviceUID))
    guard let uid, !uid.isEmpty else { throw CoreAudioCaptureError.unsupported }
    let rate = try CoreAudioProperties.sampleRate(
      .init(object: output, selector: kAudioDevicePropertyNominalSampleRate))
    return .init(id: output, uid: uid, sampleRate: rate)
  }
  func createTap(processes: [AudioObjectID]) throws -> CoreAudioTapHandle {
    guard !processes.isEmpty, processes.count <= CoreAudioProperties.maximumObjects,
      processes.allSatisfy({ $0 != kAudioObjectUnknown })
    else { throw CoreAudioCaptureError.unsupported }
    let description = CATapDescription(monoMixdownOfProcesses: processes)
    description.name = "Sillies application audio"
    description.isPrivate = true
    description.isExclusive = false
    description.isProcessRestoreEnabled = false
    description.muteBehavior = .unmuted
    var tap = AudioObjectID(kAudioObjectUnknown)
    try check(AudioHardwareCreateProcessTap(description, &tap), operation: .createTap)
    guard tap != kAudioObjectUnknown else { throw CoreAudioCaptureError.unsupported }
    return .init(id: tap, uid: description.uuid.uuidString)
  }
  func createDevice(tap: CoreAudioTapHandle, output: CoreAudioTapSelection.Output) throws
    -> AudioObjectID
  {
    let description: [String: Any] = [
      kAudioAggregateDeviceNameKey: "Sillies application audio",
      kAudioAggregateDeviceUIDKey: UUID().uuidString,
      kAudioAggregateDeviceMainSubDeviceKey: output.uid,
      kAudioAggregateDeviceSubDeviceListKey: [
        [kAudioSubDeviceUIDKey: output.uid, kAudioSubDeviceInputChannelsKey: 0]
      ],
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceIsStackedKey: false,
      kAudioAggregateDeviceTapAutoStartKey: false,
      kAudioAggregateDeviceTapListKey: [
        [kAudioSubTapUIDKey: tap.uid, kAudioSubTapDriftCompensationKey: true]
      ],
    ]
    var device = AudioObjectID(kAudioObjectUnknown)
    try check(
      AudioHardwareCreateAggregateDevice(description as CFDictionary, &device),
      operation: .createDevice)
    guard device != kAudioObjectUnknown else { throw CoreAudioCaptureError.unsupported }
    return device
  }
  func inputFormat(device: AudioObjectID) throws -> AudioStreamBasicDescription {
    let streams = try CoreAudioProperties.objects(
      .init(
        object: device, selector: kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput
      ), limit: 1)
    guard streams.count == 1, let stream = streams.first, stream != kAudioObjectUnknown else {
      throw CoreAudioCaptureError.unsupported
    }
    let format = try CoreAudioProperties.format(
      .init(object: stream, selector: kAudioStreamPropertyVirtualFormat))
    guard CoreAudioPacketEmitter.supports(format) else { throw CoreAudioCaptureError.unsupported }
    inputStreams[device] = stream
    return format
  }
  func createProcessor(device: AudioObjectID, receive: @escaping CoreAudioInputCallback) throws
    -> UUID
  {
    var processor: AudioDeviceIOProcID?
    try check(
      AudioDeviceCreateIOProcIDWithBlock(&processor, device, callbackQueue) {
        _, input, time, _, _ in
        receive(input, time.pointee)
      }, operation: .createProcessor)
    guard let processor else {
      throw CoreAudioCaptureError.native(.createProcessor, kAudioHardwareUnspecifiedError)
    }
    let token = UUID()
    processors[token] = processor
    return token
  }
  func observe(
    _ objects: CoreAudioObservedObjects,
    changed: @escaping @Sendable (CoreAudioCaptureChange) -> Void
  ) throws {
    let system = AudioObjectID(kAudioObjectSystemObject)
    try observe(
      system, selector: kAudioHardwarePropertyProcessObjectList, change: .processes,
      changed: changed)
    try observe(
      system, selector: kAudioHardwarePropertyDefaultOutputDevice, change: .configuration,
      changed: changed)
    try observe(
      objects.device, selector: kAudioDevicePropertyDeviceIsAlive, change: .configuration,
      changed: changed)
    try observe(
      objects.device, selector: kAudioDevicePropertyNominalSampleRate, change: .configuration,
      changed: changed)
    try observe(
      objects.tap, selector: kAudioTapPropertyFormat, change: .configuration, changed: changed)
    try observe(
      objects.output, selector: kAudioDevicePropertyNominalSampleRate, change: .configuration,
      changed: changed)
    if let stream = inputStreams[objects.device] {
      try observe(
        stream, selector: kAudioStreamPropertyVirtualFormat, change: .configuration,
        changed: changed)
    }
  }
  private func observe(
    _ object: AudioObjectID, selector: AudioObjectPropertySelector, change: CoreAudioCaptureChange,
    changed: @escaping @Sendable (CoreAudioCaptureChange) -> Void
  ) throws {
    var address = AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    let block: AudioObjectPropertyListenerBlock = { _, _ in changed(change) }
    try check(
      AudioObjectAddPropertyListenerBlock(object, &address, propertyQueue, block),
      operation: .observe)
    observers.append(.init(object: object, address: address, block: block))
  }
  func start(device: AudioObjectID, processor: UUID) throws {
    guard let handle = processors[processor] else {
      throw CoreAudioCaptureError.native(.start, kAudioHardwareBadObjectError)
    }
    try check(AudioDeviceStart(device, handle), operation: .start)
  }
  func stop(device: AudioObjectID, processor: UUID) throws {
    guard let handle = processors[processor] else { return }
    try checkRelease(AudioDeviceStop(device, handle), operation: .stop)
  }
  func removeObservers() throws {
    var remaining: [Observer] = []
    var failure: CoreAudioCaptureError?
    for observer in observers {
      var address = observer.address
      do {
        try checkRelease(
          AudioObjectRemovePropertyListenerBlock(
            observer.object, &address, propertyQueue, observer.block), operation: .removeObserver)
      } catch {
        remaining.append(observer)
        failure =
          (error as? CoreAudioCaptureError)
          ?? .native(.removeObserver, kAudioHardwareUnspecifiedError)
      }
    }
    observers = remaining
    if let failure { throw failure }
  }
  func destroyProcessor(device: AudioObjectID, processor: UUID) throws {
    guard let handle = processors[processor] else { return }
    try checkRelease(AudioDeviceDestroyIOProcID(device, handle), operation: .destroyProcessor)
    processors[processor] = nil
  }
  func destroyDevice(_ device: AudioObjectID) throws {
    try checkRelease(AudioHardwareDestroyAggregateDevice(device), operation: .destroyDevice)
    inputStreams[device] = nil
  }
  func destroyTap(_ tap: AudioObjectID) throws {
    try checkRelease(AudioHardwareDestroyProcessTap(tap), operation: .destroyTap)
  }
  private func check(_ status: OSStatus, operation: CoreAudioCaptureError.Operation) throws {
    if status != noErr { throw CoreAudioCaptureError.native(operation, status) }
  }
  private func checkRelease(_ status: OSStatus, operation: CoreAudioCaptureError.Operation) throws {
    guard status != noErr, status != kAudioHardwareBadObjectError,
      status != kAudioHardwareBadDeviceError
    else { return }
    throw CoreAudioCaptureError.native(operation, status)
  }
}
