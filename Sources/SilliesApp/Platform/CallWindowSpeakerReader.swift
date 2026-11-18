import AppKit
import ApplicationServices
import Foundation
import SilliesCore

/// One recording owns this worker. It never queries companion tracking's worker or another window's tree.
actor CallWindowSpeakerReader: CallSpeakerReading {
  private let makeProvider: CallSpeakerProviderFactory
  private var window: AXUIElement?
  private let accessibility: CallAccessibilityRegistry
  private let visual: any CallSpeakerVisualReading
  private var accessibilityLease: Task<CallAccessibilityRegistry.Lease, Never>?
  private var source: CallSpeakerObservation.Source?
  private var isStopped = false
  init(
    makeProvider: @escaping CallSpeakerProviderFactory,
    accessibility: CallAccessibilityRegistry,
    visual: any CallSpeakerVisualReading
  ) {
    self.accessibility = accessibility
    self.makeProvider = makeProvider
    self.visual = visual
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
    let sample = await supplement(
      Sample(evidence: result, capturedAt: start), window: window, request: request,
      interpreter: provider.visualInterpreter)
    guard !isStopped, !Task.isCancelled, let sample else { return unavailable(.unavailable) }
    return .init(
      source: source, capturedAt: sample.capturedAt, availability: .available,
      speaking: sample.evidence.speaking, participants: sample.evidence.participants,
      localParticipant: sample.evidence.localParticipant, roster: sample.evidence.roster)
  }

  private struct Sample {
    let evidence: CallSpeakerEvidence
    let capturedAt: TimeInterval
  }

  private func supplement(
    _ original: Sample, window: AXUIElement, request: CallSpeakerReadRequest,
    interpreter: (any CallSpeakerVisualInterpreting)?
  ) async -> Sample? {
    guard let interpreter, original.evidence.speaking.isEmpty,
      let layout = visualLayout(original.evidence, window: window),
      let observation = await visual.read(
        .init(
          source: .init(processID: request.target.processID, windowID: request.target.windowID),
          layout: layout, interpreter: interpreter))
    else { return original }
    guard !isStopped, !Task.isCancelled, CallSpeakerAX.matches(window, request: request),
      let bundle = request.target.bundleIdentifier,
      let provider = makeProvider(bundle)
    else { return nil }
    let scan = CallSpeakerTreeRead(
      provider: provider, startedAt: ProcessInfo.processInfo.systemUptime)
    guard var current = scan.read(window: window), !current.isAmbiguous,
      visualLayout(current, window: window) == layout,
      current.speaking.isEmpty
    else { return nil }
    for name in observation.speaking
    where name.comparisonKey != current.localParticipant?.comparisonKey {
      current.addSpeaker(name)
    }
    return .init(evidence: current, capturedAt: observation.capturedAt)
  }

  private func visualLayout(_ evidence: CallSpeakerEvidence, window: AXUIElement)
    -> CallSpeakerVisualLayout?
  {
    guard !evidence.visualTiles.isEmpty,
      let frame = CallSpeakerAX.frame(CallSpeakerAX.values([.position, .size], of: window))
    else { return nil }
    return .init(windowFrame: frame, tiles: evidence.visualTiles)
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
    await visual.stop()
    if let lease = await accessibilityLease?.value { await accessibility.release(lease) }
    accessibilityLease = nil
  }
}
