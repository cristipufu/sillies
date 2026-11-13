import CoreAudio
import SilliesCore
import Testing

@testable import SilliesAudio

@Test(arguments: [CoreAudioTestSystem.Step.tap, .device, .format, .processor, .observe, .start])
func coreAudioPartialStartupReleasesOnlyAcquiredResources(_ step: CoreAudioTestSystem.Step) throws {
  let system = CoreAudioTestSystem()
  system.state.withLock { $0.failures[step] = 1 }
  let resources = CoreAudioTapResources(system: system)
  do {
    _ = try resources.prepare(system.state.withLock { $0.selection })
    try resources.start(receive: { _, _ in }, changed: { _ in }, output: 31)
    Issue.record("Expected injected startup failure")
  } catch {}
  #expect(resources.release() == nil)
  let steps = system.state.withLock { $0.steps }
  #expect(steps.contains(.destroyTap) == (step != .tap))
  #expect(steps.contains(.destroyDevice) == ![.tap, .device].contains(step))
  #expect(steps.contains(.destroyProcessor) == [.observe, .start].contains(step))
  #expect(steps.contains(.stop) == (step == .start))
  #expect(resources.device == nil && resources.tap == nil)
}

@Test(arguments: [
  CoreAudioTestSystem.Step.removeObservers, .stop, .destroyProcessor, .destroyDevice, .destroyTap,
])
func coreAudioCleanupRetriesAndRetainsFailedHandles(_ step: CoreAudioTestSystem.Step) throws {
  let system = CoreAudioTestSystem()
  let resources = CoreAudioTapResources(system: system)
  _ = try resources.prepare(system.state.withLock { $0.selection })
  try resources.start(receive: { _, _ in }, changed: { _ in }, output: 31)
  system.state.withLock {
    $0.steps.removeAll()
    $0.failures[step] = 2
  }
  #expect(resources.release() != nil)
  let failed = system.state.withLock { $0.steps }
  if step == .stop {
    #expect(!failed.contains(.destroyProcessor) && !failed.contains(.destroyDevice))
  }
  if step == .removeObservers {
    #expect(failed.contains(.stop) && failed.contains(.destroyProcessor))
    #expect(!failed.contains(.destroyDevice))
  }
  #expect(resources.tap != nil)
  #expect(resources.release() == nil)
  #expect(resources.tap == nil && resources.device == nil)
}

@Test func coreAudioNativePermissionFailureKeepsItsTypedRecovery() {
  let failure = CoreAudioCaptureError.native(.start, kAudioDevicePermissionsError)
    .failure(category: .captureUnavailable)
  #expect(failure.category == .permissionDenied)
  #expect(failure.recovery == .openSystemAudioRecordingSettings)
  #expect(
    CoreAudioCaptureError.native(.start, kAudioHardwareUnspecifiedError)
      .failure(category: .captureUnavailable).recovery == nil)
}
