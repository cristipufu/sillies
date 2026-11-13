import AppKit
import ApplicationServices
import Foundation
import SilliesCore

/// One recording owns this worker. It never queries companion tracking's worker or another window's tree.
actor CallWindowSpeakerReader: CallSpeakerReading {
  private let makeProvider: CallSpeakerProviderFactory
  private var window: AXUIElement?
  private let accessibility: CallAccessibilityRegistry
  private var accessibilityLease: Task<CallAccessibilityRegistry.Lease, Never>?
  private var source: CallSpeakerObservation.Source?
  private var isStopped = false
  init(
    makeProvider: @escaping CallSpeakerProviderFactory,
    accessibility: CallAccessibilityRegistry
  ) {
    self.accessibility = accessibility
    self.makeProvider = makeProvider
  }

  func read(_ request: CallSpeakerReadRequest) async -> CallSpeakerObservation {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let start = ProcessInfo.processInfo.systemUptime
    let source = CallSpeakerObservation.Source(
      processID: request.target.processID, windowID: request.target.windowID)
    func unavailable(_ reason: CallSpeakerObservation.Availability) -> CallSpeakerObservation {
      .init(source: source, capturedAt: start, availability: reason)
    }
    guard !isStopped, !Task.isCancelled, request.target.processID > 0,
      request.target.processID != ProcessInfo.processInfo.processIdentifier,
      let bundle = request.target.bundleIdentifier,
      NSRunningApplication(processIdentifier: request.target.processID)?.bundleIdentifier == bundle
    else { return unavailable(.unsupported) }
    guard self.source == nil || self.source == source else { return unavailable(.unsupported) }
    self.source = source
    guard let provider = makeProvider(bundle) else { return unavailable(.unsupported) }
    guard AXIsProcessTrusted() else { return unavailable(.permissionDenied) }
    if accessibilityLease == nil {
      accessibilityLease = Task { [accessibility] in
        await accessibility.acquire(processID: source.processID)
      }
    }
    _ = await accessibilityLease?.value
    guard !isStopped, !Task.isCancelled else { return unavailable(.unavailable) }
    guard let window = boundWindow(request, deadline: start + CallSpeakerTreeRead.maximumDuration)
    else { return unavailable(.unavailable) }
    let scan = CallSpeakerTreeRead(provider: provider, startedAt: start)
    guard let result = scan.read(window: window), !result.isAmbiguous else {
      return unavailable(.unavailable)
    }
    return .init(
      source: source, capturedAt: start, availability: .available,
      speaking: result.speaking, participants: result.participants,
      localParticipant: result.localParticipant, roster: result.roster)
  }

  private func boundWindow(_ request: CallSpeakerReadRequest, deadline: TimeInterval)
    -> AXUIElement?
  {
    if let window {
      guard CallSpeakerAX.matches(window, request: request) else {
        self.window = nil
        return nil
      }
      return window
    }
    guard !Task.isCancelled else { return nil }
    let application = AXUIElementCreateApplication(request.target.processID)
    AXUIElementSetMessagingTimeout(application, CallSpeakerAX.timeout)

    guard
      let windows = CallSpeakerAX.elements(
        kAXWindowsAttribute, of: application, limit: CallSpeakerAX.maximumWindows)
    else { return nil }
    var matches: [AXUIElement] = []
    for candidate in windows {
      guard !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
      if CallSpeakerAX.matches(candidate, request: request) { matches.append(candidate) }
    }
    guard matches.count == 1, let match = matches.first else { return nil }
    window = match
    return match
  }

  func stop() async {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard !isStopped else { return }
    isStopped = true
    window = nil
    if let lease = await accessibilityLease?.value { await accessibility.release(lease) }
    accessibilityLease = nil
  }
}
